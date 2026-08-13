import Foundation

/// A 0–1 confidence score with a coarse band for display.
public struct Confidence: Codable, Hashable, Sendable, Comparable {
    public var score: Double

    public init(_ score: Double) {
        self.score = min(max(score, 0), 1)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Models sometimes emit percentages instead of fractions.
        let raw = try container.decode(Double.self)
        self.init(raw > 1 ? raw / 100 : raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(score)
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.score < rhs.score }

    public enum Level: String, Sendable {
        case low, medium, high

        public var label: String {
            switch self {
            case .low: return "Low confidence"
            case .medium: return "Fairly confident"
            case .high: return "Confident"
            }
        }
    }

    public var level: Level {
        switch score {
        case ..<0.5: return .low
        case ..<0.8: return .medium
        default: return .high
        }
    }

    public var percentText: String {
        "\(Int((score * 100).rounded()))%"
    }

    /// Below this, the app asks the user to confirm the identification rather than
    /// presenting a dossier as though it were settled fact.
    public var warrantsConfirmation: Bool { score < 0.6 }
}
