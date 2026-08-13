import Foundation
import Observation
import SwiftUI
import UIKit
import UllageCore

/// Drives one scan from photographs to dossier.
@Observable
@MainActor
final class ScanViewModel {
    enum Phase: Equatable {
        case composing
        case working
        case finished
        case failed

        var isWorking: Bool { self == .working }
    }

    private(set) var phase: Phase = .composing
    private(set) var images: [CapturedImage] = []
    private(set) var log = ResearchLog()
    private(set) var reading: LabelReading?
    private(set) var dossier: WineDossier?
    private(set) var errorMessage: String?
    private(set) var errorSuggestion: String?
    private(set) var isRetryable = false

    private var task: Task<Void, Never>?
    private let makeService: () -> WineIntelligenceService

    /// Nonisolated so a `View` can build one in a property initialiser, which runs outside the
    /// main actor even though SwiftUI only ever calls it from the main thread.
    nonisolated init(makeService: @escaping () -> WineIntelligenceService) {
        self.makeService = makeService
    }

    struct CapturedImage: Identifiable, Equatable {
        let id = UUID()
        var image: UIImage
        var role: LabelImage.Role
        var jpegData: Data

        var labelImage: LabelImage {
            LabelImage(jpegData: jpegData, role: role)
        }
    }

    var canStart: Bool { !images.isEmpty && !phase.isWorking }

    // MARK: - Photographs

    func add(_ image: UIImage) {
        guard let data = ImagePreparer.prepare(image) else { return }
        // The first photograph is the front label; anything after it is most likely the back,
        // which is where the alcohol level and the producer's own notes tend to live.
        let role: LabelImage.Role = images.isEmpty ? .front : (images.count == 1 ? .back : .other)
        images.append(CapturedImage(image: image, role: role, jpegData: data))
    }

    func remove(_ captured: CapturedImage) {
        images.removeAll { $0.id == captured.id }
        reassignRoles()
    }

    private func reassignRoles() {
        for index in images.indices {
            images[index].role = index == 0 ? .front : (index == 1 ? .back : .other)
        }
    }

    // MARK: - Running

    func start() {
        guard !images.isEmpty else { return }
        let payload = images.map(\.labelImage)
        run { service in service.scan(images: payload) }
    }

    func research(manualEntry: String) {
        let entry = manualEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        run { service in service.research(manualEntry: entry) }
    }

    func retry() {
        if images.isEmpty, let reading {
            research(manualEntry: reading.researchSubject)
        } else {
            start()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase.isWorking {
            phase = .composing
            log.removeAll()
        }
    }

    func reset() {
        cancel()
        images.removeAll()
        log.removeAll()
        reading = nil
        dossier = nil
        errorMessage = nil
        errorSuggestion = nil
        phase = .composing
    }

    private func run(
        _ makeStream: @escaping (WineIntelligenceService) -> AsyncThrowingStream<ScanProgress, Error>
    ) {
        task?.cancel()
        phase = .working
        log.removeAll()
        dossier = nil
        errorMessage = nil
        errorSuggestion = nil
        isRetryable = false

        let service = makeService()
        task = Task { [weak self] in
            do {
                for try await progress in makeStream(service) {
                    guard !Task.isCancelled else { return }
                    self?.apply(progress)
                }
                // A stream that ends without a dossier and without throwing means it was
                // cancelled from underneath us; leaving the spinner up would be a lie.
                if let self, self.phase.isWorking {
                    self.phase = .composing
                }
            } catch is CancellationError {
                self?.phase = .composing
            } catch {
                self?.fail(with: error)
            }
        }
    }

    private func apply(_ progress: ScanProgress) {
        withAnimation(.easeOut(duration: 0.2)) {
            log.apply(progress)
        }
        switch progress {
        case let .identified(reading):
            self.reading = reading
        case let .finished(dossier):
            self.dossier = dossier
            phase = .finished
        default:
            break
        }
    }

    private func fail(with error: Error) {
        phase = .failed
        if let scanError = error as? ScanError {
            errorMessage = scanError.errorDescription
            errorSuggestion = scanError.recoverySuggestion
            isRetryable = false
        } else if let responsesError = error as? ResponsesError {
            errorMessage = responsesError.errorDescription
            errorSuggestion = responsesError.isRetryable ? nil : "Check your key and model in Settings."
            isRetryable = responsesError.isRetryable
        } else {
            errorMessage = error.localizedDescription
            isRetryable = true
        }
    }
}
