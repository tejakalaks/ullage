import Foundation
import UllageCore

/// The wine knowledge the app is built on.
///
/// A protocol so demo mode, previews and tests can stand in for the live service, and so a
/// server-side proxy can replace the direct API calls later without touching the UI.
protocol WineIntelligenceService: Sendable {
    /// Runs both passes, reporting progress as it goes.
    func scan(images: [LabelImage]) -> AsyncThrowingStream<ScanProgress, Error>

    /// Researches a wine the user described or corrected by hand, skipping the vision pass.
    func research(manualEntry: String) -> AsyncThrowingStream<ScanProgress, Error>
}

/// A photograph on its way to the model.
struct LabelImage: Hashable, Sendable {
    var jpegData: Data
    var role: Role

    enum Role: String, Hashable, Sendable, CaseIterable {
        case front
        case back
        case other

        var promptDescription: String {
            switch self {
            case .front: return "front label"
            case .back: return "back label"
            case .other: return "another view of the bottle"
            }
        }

        var displayName: String {
            switch self {
            case .front: return "Front"
            case .back: return "Back"
            case .other: return "Other"
            }
        }
    }

    var dataURL: String {
        "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    var payload: ResponsesRequest.ImagePayload {
        ResponsesRequest.ImagePayload(dataURL: dataURL, role: role.promptDescription)
    }
}

/// Reasons a scan can fail that are the app's business rather than the API's.
enum ScanError: LocalizedError {
    case noImages
    case notAWineLabel(reason: String?)
    case unidentifiable

    var errorDescription: String? {
        switch self {
        case .noImages:
            return "There is no photograph to look at."
        case let .notAWineLabel(reason):
            return reason ?? "That does not look like a wine label."
        case .unidentifiable:
            return "The label could not be made out well enough to research the wine."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noImages:
            return nil
        case .notAWineLabel:
            return "Point the camera at the front of a wine bottle."
        case .unidentifiable:
            return "Try again with the label filling more of the frame, or add a photo of the back label."
        }
    }
}
