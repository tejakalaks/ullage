import Foundation
import UllageCore

/// A stand-in that replays a realistic scan without a network or an API key.
///
/// This is what demo mode runs on, and what SwiftUI previews use. It walks the same progress
/// sequence as the real service, with pauses, so the interface is exercised as it will
/// actually behave rather than snapping straight to a finished dossier.
struct MockWineIntelligence: WineIntelligenceService {
    var dossier: WineDossier = SampleData.dossier
    var reading: LabelReading = SampleData.labelReading
    /// Set to zero in tests so they do not sit waiting.
    var pace: Duration = .milliseconds(650)
    var failure: (any Error & Sendable)?

    func scan(images: [LabelImage]) -> AsyncThrowingStream<ScanProgress, Error> {
        replay(includeIdentification: true)
    }

    func research(manualEntry: String) -> AsyncThrowingStream<ScanProgress, Error> {
        replay(includeIdentification: false)
    }

    private func replay(includeIdentification: Bool) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let failure {
                        try await Task.sleep(for: pace)
                        throw failure
                    }
                    if includeIdentification {
                        continuation.yield(.readingLabel)
                        try await Task.sleep(for: pace * 2)
                        continuation.yield(.identified(reading))
                    }
                    continuation.yield(.researching)
                    try await Task.sleep(for: pace)

                    for query in reading.suggestedQueries.prefix(3) {
                        continuation.yield(.searching(query: query))
                        try await Task.sleep(for: pace)
                        continuation.yield(.searchFinished(query: query))
                    }

                    continuation.yield(.composing)
                    try await Task.sleep(for: pace)
                    continuation.yield(.finished(dossier))
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
}
