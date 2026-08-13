import Foundation

/// What the vision pass made of the photograph — the output of stage A.
///
/// This is deliberately not "OCR output". The model is asked to interpret the bottle the way
/// a person familiar with wine would: recognising that "Ch. Musar" is a producer, that
/// "Gevrey-Chambertin 1er Cru" is an appellation and a rank rather than a brand name, and
/// that the small print on the back is importer boilerplate. It also proposes the searches
/// stage B should run, because the model knows better than a hardcoded template what would
/// pin down this particular bottle.
public struct LabelReading: Codable, Hashable, Sendable {
    /// False when the photo is not a wine bottle at all, which is worth saying plainly
    /// instead of hallucinating a dossier for a bottle of olive oil.
    public var isWineLabel: Bool
    /// Why identification failed, when `isWineLabel` is false or nothing could be read.
    public var rejectionReason: String?

    public var producer: String?
    public var cuvee: String?
    /// Nil for non-vintage bottles; check `isNonVintage` to tell that apart from "unreadable".
    public var vintage: Int?
    public var isNonVintage: Bool
    public var appellation: String?
    public var region: String?
    public var country: String?
    public var wineType: WineType?
    public var alcoholPercent: Double?
    public var bottleSizeMilliliters: Int?
    public var classification: String?
    public var importer: String?

    /// Anything else legible and potentially identifying: cask numbers, bottling dates,
    /// "mis en bouteille au château", cuvée codes.
    public var otherLabelText: [String]
    /// How the label looks, which is a real identification signal for wines whose text is
    /// worn, foreign-script, or deliberately minimal.
    public var visualDescription: String?

    public var confidence: Confidence
    /// Alternatives when the label is ambiguous, best first.
    public var alternatives: [Alternative]
    /// Search queries the model wants stage B to run.
    public var suggestedQueries: [String]

    public struct Alternative: Codable, Hashable, Sendable {
        public var description: String
        public var confidence: Confidence

        public init(description: String, confidence: Confidence) {
            self.description = description
            self.confidence = confidence
        }
    }

    public init(
        isWineLabel: Bool = true,
        rejectionReason: String? = nil,
        producer: String? = nil,
        cuvee: String? = nil,
        vintage: Int? = nil,
        isNonVintage: Bool = false,
        appellation: String? = nil,
        region: String? = nil,
        country: String? = nil,
        wineType: WineType? = nil,
        alcoholPercent: Double? = nil,
        bottleSizeMilliliters: Int? = nil,
        classification: String? = nil,
        importer: String? = nil,
        otherLabelText: [String] = [],
        visualDescription: String? = nil,
        confidence: Confidence = Confidence(0),
        alternatives: [Alternative] = [],
        suggestedQueries: [String] = []
    ) {
        self.isWineLabel = isWineLabel
        self.rejectionReason = rejectionReason
        self.producer = producer
        self.cuvee = cuvee
        self.vintage = vintage
        self.isNonVintage = isNonVintage
        self.appellation = appellation
        self.region = region
        self.country = country
        self.wineType = wineType
        self.alcoholPercent = alcoholPercent
        self.bottleSizeMilliliters = bottleSizeMilliliters
        self.classification = classification
        self.importer = importer
        self.otherLabelText = otherLabelText
        self.visualDescription = visualDescription
        self.confidence = confidence
        self.alternatives = alternatives
        self.suggestedQueries = suggestedQueries
    }

    private enum CodingKeys: String, CodingKey {
        case isWineLabel = "is_wine_label"
        case rejectionReason = "rejection_reason"
        case producer
        case cuvee
        case vintage
        case isNonVintage = "is_non_vintage"
        case appellation
        case region
        case country
        case wineType = "wine_type"
        case alcoholPercent = "alcohol_percent"
        case bottleSizeMilliliters = "bottle_size_ml"
        case classification
        case importer
        case otherLabelText = "other_label_text"
        case visualDescription = "visual_description"
        case confidence
        case alternatives
        case suggestedQueries = "suggested_queries"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isWineLabel = c.lenient(Bool.self, .isWineLabel, default: true)
        rejectionReason = c.lenientString(.rejectionReason)
        producer = c.lenientString(.producer)
        cuvee = c.lenientString(.cuvee)
        vintage = c.lenient(Int.self, .vintage)
        isNonVintage = c.lenient(Bool.self, .isNonVintage, default: false)
        appellation = c.lenientString(.appellation)
        region = c.lenientString(.region)
        country = c.lenientString(.country)
        wineType = c.lenient(WineType.self, .wineType)
        alcoholPercent = c.lenient(Double.self, .alcoholPercent)
        bottleSizeMilliliters = c.lenient(Int.self, .bottleSizeMilliliters)
        classification = c.lenientString(.classification)
        importer = c.lenientString(.importer)
        otherLabelText = c.lenient([String].self, .otherLabelText, default: [])
        visualDescription = c.lenientString(.visualDescription)
        confidence = c.lenient(Confidence.self, .confidence, default: Confidence(0))
        alternatives = c.lenient([Alternative].self, .alternatives, default: [])
        suggestedQueries = c.lenient([String].self, .suggestedQueries, default: [])
    }

    /// One-line identification for the header that appears as soon as stage A lands.
    public var displayTitle: String {
        var parts: [String] = []
        if let producer { parts.append(producer) }
        if let cuvee, cuvee.caseInsensitiveCompare(producer ?? "") != .orderedSame {
            parts.append(cuvee)
        }
        if parts.isEmpty {
            parts.append(appellation ?? region ?? "Unidentified wine")
        }
        if let vintage {
            parts.append(String(vintage))
        } else if isNonVintage {
            parts.append("NV")
        }
        return parts.joined(separator: " ")
    }

    public var displaySubtitle: String? {
        [appellation, region, country]
            .compactMap { $0 }
            .removingDuplicatesCaseInsensitively()
            .prefix(2)
            .joined(separator: ", ")
            .nilIfBlank
    }

    /// True when there is enough to research. Without a producer or an appellation, a web
    /// search would just be guessing, and it is better to ask for a clearer photo.
    public var isIdentifiable: Bool {
        isWineLabel && (producer != nil || cuvee != nil || appellation != nil)
    }

    /// Compact description handed to the research pass as its subject.
    public var researchSubject: String {
        var parts: [String] = []
        if let producer { parts.append(producer) }
        if let cuvee { parts.append(cuvee) }
        if let vintage { parts.append(String(vintage)) } else if isNonVintage { parts.append("NV") }
        if let appellation { parts.append(appellation) }
        if let region, region.caseInsensitiveCompare(appellation ?? "") != .orderedSame {
            parts.append(region)
        }
        if let country { parts.append(country) }
        return parts.removingDuplicatesCaseInsensitively().joined(separator: ", ")
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Array where Element == String {
    func removingDuplicatesCaseInsensitively() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
