import Foundation

public enum WineType: String, Codable, Hashable, Sendable, CaseIterable {
    case red
    case white
    case rose
    case orange
    case sparkling
    case dessert
    case fortified
    case other

    /// Tolerates the many spellings a model might reach for ("rosé", "skin contact",
    /// "champagne") rather than failing the decode over vocabulary.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WineType(loosely: raw) ?? .other
    }

    public init?(loosely raw: String) {
        let normalized = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "red", "rouge", "tinto", "rosso", "rot":
            self = .red
        case "white", "blanc", "blanco", "bianco", "weiss":
            self = .white
        case "rose", "rosado", "rosato", "blush":
            self = .rose
        case "orange", "amber", "skin contact", "skin-contact":
            self = .orange
        case "sparkling", "champagne", "cremant", "cava", "prosecco", "espumante", "sekt", "petnat", "pet-nat":
            self = .sparkling
        case "dessert", "sweet", "late harvest", "ice wine", "icewine", "botrytis", "sauternes":
            self = .dessert
        case "fortified", "port", "sherry", "madeira", "marsala", "vin doux naturel":
            self = .fortified
        case "other":
            self = .other
        default:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .red: return "Red"
        case .white: return "White"
        case .rose: return "Rosé"
        case .orange: return "Orange"
        case .sparkling: return "Sparkling"
        case .dessert: return "Dessert"
        case .fortified: return "Fortified"
        case .other: return "Wine"
        }
    }

    /// Fallback serving temperature when no source gives one, in Celsius.
    public var conventionalServingTemperature: ClosedRangeBox {
        switch self {
        case .red: return ClosedRangeBox(lower: 16, upper: 18)
        case .white, .orange: return ClosedRangeBox(lower: 8, upper: 12)
        case .rose: return ClosedRangeBox(lower: 8, upper: 10)
        case .sparkling: return ClosedRangeBox(lower: 6, upper: 8)
        case .dessert: return ClosedRangeBox(lower: 6, upper: 10)
        case .fortified: return ClosedRangeBox(lower: 12, upper: 16)
        case .other: return ClosedRangeBox(lower: 10, upper: 16)
        }
    }
}
