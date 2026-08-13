import Foundation
import UllageCore

/// The live pipeline: look at the bottle, then research it.
struct OpenAIWineIntelligence: WineIntelligenceService {
    var client: ResponsesClient
    var configuration: ModelConfiguration
    /// Injected so tests and previews are not at the mercy of the calendar.
    var currentYear: @Sendable () -> Int = { Calendar.current.component(.year, from: Date()) }

    init(
        apiKey: String,
        configuration: ModelConfiguration,
        session: URLSession = .shared
    ) {
        self.client = ResponsesClient(apiKey: apiKey, session: session)
        self.configuration = configuration
    }

    func scan(images: [LabelImage]) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !images.isEmpty else { throw ScanError.noImages }

                    continuation.yield(.readingLabel)
                    let reading = try await readLabel(images: images)

                    guard reading.isWineLabel else {
                        throw ScanError.notAWineLabel(reason: reading.rejectionReason)
                    }
                    guard reading.isIdentifiable else {
                        throw ScanError.unidentifiable
                    }
                    continuation.yield(.identified(reading))

                    let prompt = StagePrompts.researchRequest(for: reading, currentYear: currentYear())
                    try await runResearch(
                        prompt: prompt,
                        images: images,
                        fallbackIdentity: reading,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func research(manualEntry: String) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let prompt = StagePrompts.researchRequest(
                        forManualEntry: manualEntry,
                        currentYear: currentYear()
                    )
                    try await runResearch(
                        prompt: prompt,
                        images: [],
                        fallbackIdentity: nil,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Stage A

    private func readLabel(images: [LabelImage]) async throws -> LabelReading {
        let body = ResponsesRequest.labelReading(
            images: images.map(\.payload),
            options: configuration.identificationOptions,
            stream: false
        )
        let envelope = try await client.send(body)
        if let refusal = envelope.refusal {
            throw ResponsesError.refused(refusal)
        }
        guard !envelope.outputText.isEmpty else {
            throw ResponsesError.emptyOutput
        }
        return try ModelOutputDecoder.decodeLabelReading(from: envelope.outputText)
    }

    // MARK: - Stage B

    private func runResearch(
        prompt: String,
        images: [LabelImage],
        fallbackIdentity: LabelReading?,
        continuation: AsyncThrowingStream<ScanProgress, Error>.Continuation
    ) async throws {
        continuation.yield(.researching)

        let body = ResponsesRequest.research(
            prompt: prompt,
            images: images.map(\.payload),
            options: configuration.researchOptions,
            stream: true
        )

        var envelope: ResponsesEnvelope?
        var announcedComposing = false

        for try await event in client.stream(body) {
            switch event {
            case let .searchStarted(query):
                continuation.yield(.searching(query: query))
            case let .searchCompleted(query):
                continuation.yield(.searchFinished(query: query))
            case .textDelta:
                // The dossier JSON is arriving. Streaming partial JSON into the UI would mean
                // rendering a half-parsed object, so this only flips the status line once.
                if !announcedComposing {
                    announcedComposing = true
                    continuation.yield(.composing)
                }
            case .reasoningSummary:
                break
            case let .completed(finished):
                envelope = finished
            case let .failed(error):
                throw error
            }
        }

        guard let envelope else { throw ResponsesError.emptyOutput }
        if let refusal = envelope.refusal {
            throw ResponsesError.refused(refusal)
        }
        guard !envelope.outputText.isEmpty else {
            throw ResponsesError.emptyOutput
        }

        var dossier = try ModelOutputDecoder
            .decodeDossier(from: envelope.outputText)
            .mergingAnnotatedSources(envelope.annotatedURLs)

        // If research somehow lost the producer, the label reading is a better answer than
        // "Unknown producer".
        if dossier.identity.producer == "Unknown producer", let fallback = fallbackIdentity?.producer {
            dossier.identity.producer = fallback
        }

        continuation.yield(.finished(dossier))
    }
}

/// Which models to use and how hard to make them think.
struct ModelConfiguration: Hashable, Sendable, Codable {
    var identificationModel: String
    var researchModel: String
    var enableWebSearch: Bool
    var researchEffort: String?

    static let `default` = ModelConfiguration(
        identificationModel: "gpt-5-mini",
        researchModel: "gpt-5",
        enableWebSearch: true,
        researchEffort: "medium"
    )

    /// Cheaper and quicker, at the cost of depth.
    static let economical = ModelConfiguration(
        identificationModel: "gpt-5-mini",
        researchModel: "gpt-5-mini",
        enableWebSearch: true,
        researchEffort: "low"
    )

    var identificationOptions: ResponsesRequest.Options {
        // Reading a label is perception, not deliberation: minimal effort keeps the first
        // result on screen quickly, which is what the whole two-pass split is for.
        ResponsesRequest.Options(
            model: identificationModel,
            enableWebSearch: false,
            reasoningEffort: "low",
            maxOutputTokens: 2_000
        )
    }

    var researchOptions: ResponsesRequest.Options {
        ResponsesRequest.Options(
            model: researchModel,
            enableWebSearch: enableWebSearch,
            reasoningEffort: researchEffort,
            maxOutputTokens: 8_000
        )
    }
}
