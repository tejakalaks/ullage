import Foundation

/// Everything the app knows about one bottle — the output of the research pass and the
/// single contract shared by the JSON schema, the decoder and every view.
public struct WineDossier: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var identity: Identity
    public var origin: Origin
    public var composition: [GrapeShare]
    public var winemaking: Winemaking
    public var tasting: Tasting
    public var drinkingWindow: DrinkingWindow
    public var pairings: [String]
    public var ratings: [Rating]
    public var priceEstimate: PriceEstimate?
    public var sources: [Citation]
    public var overallConfidence: Confidence
    /// Where the research came up short, in plain language, so the UI can say what is missing
    /// instead of quietly showing a thinner page.
    public var researchNotes: String?
    public var generatedAt: Date

    public init(
        id: UUID = UUID(),
        identity: Identity,
        origin: Origin = Origin(),
        composition: [GrapeShare] = [],
        winemaking: Winemaking = Winemaking(),
        tasting: Tasting = Tasting(),
        drinkingWindow: DrinkingWindow = DrinkingWindow(),
        pairings: [String] = [],
        ratings: [Rating] = [],
        priceEstimate: PriceEstimate? = nil,
        sources: [Citation] = [],
        overallConfidence: Confidence = Confidence(0),
        researchNotes: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.identity = identity
        self.origin = origin
        self.composition = composition
        self.winemaking = winemaking
        self.tasting = tasting
        self.drinkingWindow = drinkingWindow
        self.pairings = pairings
        self.ratings = ratings
        self.priceEstimate = priceEstimate
        self.sources = sources
        self.overallConfidence = overallConfidence
        self.researchNotes = researchNotes
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case identity
        case origin
        case composition
        case winemaking
        case tasting
        case drinkingWindow = "drinking_window"
        case pairings
        case ratings
        case priceEstimate = "price_estimate"
        case sources
        case overallConfidence = "overall_confidence"
        case researchNotes = "research_notes"
        case generatedAt = "generated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The model never supplies these two; they are the app's own bookkeeping and are
        // regenerated unless a stored dossier is being re-read.
        id = c.lenient(UUID.self, .id, default: UUID())
        generatedAt = c.lenient(Date.self, .generatedAt, default: Date())
        identity = try c.decode(Identity.self, forKey: .identity)
        origin = c.lenient(Origin.self, .origin, default: Origin())
        composition = c.lenient([GrapeShare].self, .composition, default: [])
        winemaking = c.lenient(Winemaking.self, .winemaking, default: Winemaking())
        tasting = c.lenient(Tasting.self, .tasting, default: Tasting())
        drinkingWindow = c.lenient(DrinkingWindow.self, .drinkingWindow, default: DrinkingWindow())
        pairings = c.lenient([String].self, .pairings, default: [])
        ratings = c.lenient([Rating].self, .ratings, default: [])
        priceEstimate = c.lenient(PriceEstimate.self, .priceEstimate)
        sources = c.lenient([Citation].self, .sources, default: [])
        overallConfidence = c.lenient(Confidence.self, .overallConfidence, default: Confidence(0.5))
        researchNotes = c.lenientString(.researchNotes)
    }
}

extension WineDossier {
    public struct Identity: Codable, Hashable, Sendable {
        public var producer: String
        public var wineName: String?
        public var vintage: Int?
        public var isNonVintage: Bool
        public var wineType: WineType
        public var alcoholPercent: Double?
        public var bottleSizeMilliliters: Int?
        /// One or two sentences on why this bottle is interesting — the line a good wine
        /// merchant would lead with.
        public var summary: String?

        public init(
            producer: String,
            wineName: String? = nil,
            vintage: Int? = nil,
            isNonVintage: Bool = false,
            wineType: WineType = .other,
            alcoholPercent: Double? = nil,
            bottleSizeMilliliters: Int? = nil,
            summary: String? = nil
        ) {
            self.producer = producer
            self.wineName = wineName
            self.vintage = vintage
            self.isNonVintage = isNonVintage
            self.wineType = wineType
            self.alcoholPercent = alcoholPercent
            self.bottleSizeMilliliters = bottleSizeMilliliters
            self.summary = summary
        }

        private enum CodingKeys: String, CodingKey {
            case producer
            case wineName = "wine_name"
            case vintage
            case isNonVintage = "is_non_vintage"
            case wineType = "wine_type"
            case alcoholPercent = "alcohol_percent"
            case bottleSizeMilliliters = "bottle_size_ml"
            case summary
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            producer = c.lenientString(.producer) ?? "Unknown producer"
            wineName = c.lenientString(.wineName)
            vintage = c.lenient(Int.self, .vintage)
            isNonVintage = c.lenient(Bool.self, .isNonVintage, default: false)
            wineType = c.lenient(WineType.self, .wineType, default: .other)
            alcoholPercent = c.lenient(Double.self, .alcoholPercent)
            bottleSizeMilliliters = c.lenient(Int.self, .bottleSizeMilliliters)
            summary = c.lenientString(.summary)
        }

        public var vintageText: String {
            if let vintage { return String(vintage) }
            return isNonVintage ? "NV" : "—"
        }

        public var displayTitle: String {
            guard let wineName, wineName.caseInsensitiveCompare(producer) != .orderedSame else {
                return producer
            }
            return "\(producer) \(wineName)"
        }
    }

    public struct Origin: Codable, Hashable, Sendable {
        public var country: Attributed<String>?
        public var region: Attributed<String>?
        public var subregion: Attributed<String>?
        public var appellation: Attributed<String>?
        public var vineyard: Attributed<String>?
        /// "Grand Cru", "Riserva", "Gran Reserva", "1er Cru Classé".
        public var classification: Attributed<String>?
        /// What makes this place taste the way it does: soils, altitude, climate.
        public var terroirNotes: Attributed<String>?

        public init(
            country: Attributed<String>? = nil,
            region: Attributed<String>? = nil,
            subregion: Attributed<String>? = nil,
            appellation: Attributed<String>? = nil,
            vineyard: Attributed<String>? = nil,
            classification: Attributed<String>? = nil,
            terroirNotes: Attributed<String>? = nil
        ) {
            self.country = country
            self.region = region
            self.subregion = subregion
            self.appellation = appellation
            self.vineyard = vineyard
            self.classification = classification
            self.terroirNotes = terroirNotes
        }

        private enum CodingKeys: String, CodingKey {
            case country, region, subregion, appellation, vineyard, classification
            case terroirNotes = "terroir_notes"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            country = c.lenient(Attributed<String>.self, .country)?.nilIfBlank
            region = c.lenient(Attributed<String>.self, .region)?.nilIfBlank
            subregion = c.lenient(Attributed<String>.self, .subregion)?.nilIfBlank
            appellation = c.lenient(Attributed<String>.self, .appellation)?.nilIfBlank
            vineyard = c.lenient(Attributed<String>.self, .vineyard)?.nilIfBlank
            classification = c.lenient(Attributed<String>.self, .classification)?.nilIfBlank
            terroirNotes = c.lenient(Attributed<String>.self, .terroirNotes)?.nilIfBlank
        }

        /// Broad to narrow, deduplicated, for the origin breadcrumb.
        public var hierarchy: [Attributed<String>] {
            var seen = Set<String>()
            return [country, region, subregion, appellation, vineyard]
                .compactMap { $0 }
                .filter { seen.insert($0.value.lowercased()).inserted }
        }

        public var breadcrumb: String? {
            let names = hierarchy.map(\.value)
            return names.isEmpty ? nil : names.joined(separator: " › ")
        }
    }

    /// A grape and how much of the blend it makes up.
    public struct GrapeShare: Codable, Hashable, Sendable, Identifiable {
        public var name: String
        /// Nil when the blend is known but the proportions are not published.
        public var percentage: Double?

        public var id: String { name }

        public init(name: String, percentage: Double? = nil) {
            self.name = name
            self.percentage = percentage
        }

        private enum CodingKeys: String, CodingKey {
            case name, percentage
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = c.lenientString(.name) ?? "Unknown"
            percentage = c.lenient(Double.self, .percentage)
        }

        public var percentageText: String? {
            guard let percentage else { return nil }
            return percentage == percentage.rounded()
                ? "\(Int(percentage))%"
                : String(format: "%.1f%%", percentage)
        }
    }

    public struct Winemaking: Codable, Hashable, Sendable {
        /// The producer's own words about the wine, quoted or closely paraphrased.
        /// This is the field the whole app is really for.
        public var winemakerNotes: Attributed<String>?
        public var vinification: Attributed<String>?
        /// Barrel regime: vessel, size, proportion of new oak, time in wood.
        public var aging: Attributed<String>?
        public var viticulture: Attributed<String>?
        public var isOrganic: Bool?
        public var isBiodynamic: Bool?
        public var isVegan: Bool?
        public var productionQuantity: Attributed<String>?

        public init(
            winemakerNotes: Attributed<String>? = nil,
            vinification: Attributed<String>? = nil,
            aging: Attributed<String>? = nil,
            viticulture: Attributed<String>? = nil,
            isOrganic: Bool? = nil,
            isBiodynamic: Bool? = nil,
            isVegan: Bool? = nil,
            productionQuantity: Attributed<String>? = nil
        ) {
            self.winemakerNotes = winemakerNotes
            self.vinification = vinification
            self.aging = aging
            self.viticulture = viticulture
            self.isOrganic = isOrganic
            self.isBiodynamic = isBiodynamic
            self.isVegan = isVegan
            self.productionQuantity = productionQuantity
        }

        private enum CodingKeys: String, CodingKey {
            case winemakerNotes = "winemaker_notes"
            case vinification
            case aging
            case viticulture
            case isOrganic = "is_organic"
            case isBiodynamic = "is_biodynamic"
            case isVegan = "is_vegan"
            case productionQuantity = "production_quantity"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            winemakerNotes = c.lenient(Attributed<String>.self, .winemakerNotes)?.nilIfBlank
            vinification = c.lenient(Attributed<String>.self, .vinification)?.nilIfBlank
            aging = c.lenient(Attributed<String>.self, .aging)?.nilIfBlank
            viticulture = c.lenient(Attributed<String>.self, .viticulture)?.nilIfBlank
            isOrganic = c.lenient(Bool.self, .isOrganic)
            isBiodynamic = c.lenient(Bool.self, .isBiodynamic)
            isVegan = c.lenient(Bool.self, .isVegan)
            productionQuantity = c.lenient(Attributed<String>.self, .productionQuantity)?.nilIfBlank
        }

        public var certifications: [String] {
            var result: [String] = []
            if isOrganic == true { result.append("Organic") }
            if isBiodynamic == true { result.append("Biodynamic") }
            if isVegan == true { result.append("Vegan") }
            return result
        }

        public var isEmpty: Bool {
            winemakerNotes == nil && vinification == nil && aging == nil
                && viticulture == nil && productionQuantity == nil && certifications.isEmpty
        }
    }

    public struct Tasting: Codable, Hashable, Sendable {
        public var nose: Attributed<String>?
        public var palate: Attributed<String>?
        public var finish: Attributed<String>?
        public var structure: Structure?

        public init(
            nose: Attributed<String>? = nil,
            palate: Attributed<String>? = nil,
            finish: Attributed<String>? = nil,
            structure: Structure? = nil
        ) {
            self.nose = nose
            self.palate = palate
            self.finish = finish
            self.structure = structure
        }

        private enum CodingKeys: String, CodingKey {
            case nose, palate, finish, structure
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nose = c.lenient(Attributed<String>.self, .nose)?.nilIfBlank
            palate = c.lenient(Attributed<String>.self, .palate)?.nilIfBlank
            finish = c.lenient(Attributed<String>.self, .finish)?.nilIfBlank
            structure = c.lenient(Structure.self, .structure)
        }

        public var isEmpty: Bool {
            nose == nil && palate == nil && finish == nil && structure == nil
        }

        /// The classic axes, each 1–5, for the bar chart.
        public struct Structure: Codable, Hashable, Sendable {
            public var body: Int?
            public var acidity: Int?
            public var tannin: Int?
            public var sweetness: Int?

            public init(body: Int? = nil, acidity: Int? = nil, tannin: Int? = nil, sweetness: Int? = nil) {
                self.body = Self.clamp(body)
                self.acidity = Self.clamp(acidity)
                self.tannin = Self.clamp(tannin)
                self.sweetness = Self.clamp(sweetness)
            }

            private static func clamp(_ value: Int?) -> Int? {
                guard let value else { return nil }
                return min(max(value, 1), 5)
            }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.init(
                    body: c.lenient(Int.self, .body),
                    acidity: c.lenient(Int.self, .acidity),
                    tannin: c.lenient(Int.self, .tannin),
                    sweetness: c.lenient(Int.self, .sweetness)
                )
            }

            public struct Axis: Hashable, Sendable, Identifiable {
                public var name: String
                public var value: Int

                public var id: String { name }
            }

            /// Only the axes that were actually reported, in a sensible reading order. An axis
            /// the sources did not mention is left out rather than drawn as an empty bar.
            public var axes: [Axis] {
                [
                    body.map { Axis(name: "Body", value: $0) },
                    acidity.map { Axis(name: "Acidity", value: $0) },
                    tannin.map { Axis(name: "Tannin", value: $0) },
                    sweetness.map { Axis(name: "Sweetness", value: $0) }
                ].compactMap { $0 }
            }
        }
    }

    public struct Rating: Codable, Hashable, Sendable, Identifiable {
        public var critic: String
        public var score: String
        /// Usually 100 or 20; kept as a number so scores can be compared and drawn.
        public var scale: Double?
        public var numericScore: Double?
        public var reviewExcerpt: String?
        public var sourceIndex: Int?

        public var id: String { "\(critic)-\(score)" }

        public init(
            critic: String,
            score: String,
            scale: Double? = nil,
            numericScore: Double? = nil,
            reviewExcerpt: String? = nil,
            sourceIndex: Int? = nil
        ) {
            self.critic = critic
            self.score = score
            self.scale = scale
            self.numericScore = numericScore
            self.reviewExcerpt = reviewExcerpt
            self.sourceIndex = sourceIndex
        }

        private enum CodingKeys: String, CodingKey {
            case critic
            case score
            case scale
            case numericScore = "numeric_score"
            case reviewExcerpt = "review_excerpt"
            case sourceIndex = "source_index"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            critic = c.lenientString(.critic) ?? "Critic"
            score = c.lenientString(.score) ?? ""
            scale = c.lenient(Double.self, .scale)
            numericScore = c.lenient(Double.self, .numericScore)
            reviewExcerpt = c.lenientString(.reviewExcerpt)
            sourceIndex = c.lenient(Int.self, .sourceIndex)
        }

        public var displayScore: String {
            guard let scale, !score.isEmpty else { return score }
            return score.contains("/") ? score : "\(score)/\(Int(scale))"
        }
    }

    public struct PriceEstimate: Codable, Hashable, Sendable {
        public var low: Double?
        public var high: Double?
        public var currency: String
        /// e.g. "UK retail, 2026" — a price without a market and a date is meaningless.
        public var market: String?
        public var provenance: Provenance
        public var sourceIndices: [Int]

        public init(
            low: Double? = nil,
            high: Double? = nil,
            currency: String = "USD",
            market: String? = nil,
            provenance: Provenance = .inference,
            sourceIndices: [Int] = []
        ) {
            self.low = low
            self.high = high
            self.currency = currency
            self.market = market
            self.provenance = provenance
            self.sourceIndices = sourceIndices
        }

        private enum CodingKeys: String, CodingKey {
            case low, high, currency, market, provenance
            case sourceIndices = "source_indices"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            low = c.lenient(Double.self, .low)
            high = c.lenient(Double.self, .high)
            currency = c.lenientString(.currency) ?? "USD"
            market = c.lenientString(.market)
            provenance = c.lenient(Provenance.self, .provenance, default: .inference)
            sourceIndices = c.lenient([Int].self, .sourceIndices, default: [])
        }

        public var isEmpty: Bool { low == nil && high == nil }

        public var displayRange: String? {
            let symbol = Self.symbol(for: currency)
            let format: (Double) -> String = { value in
                value == value.rounded()
                    ? "\(symbol)\(Int(value))"
                    : String(format: "\(symbol)%.2f", value)
            }
            switch (low, high) {
            case let (low?, high?):
                return low == high ? format(low) : "\(format(low))–\(format(high))"
            case let (low?, nil):
                return "from \(format(low))"
            case let (nil, high?):
                return "up to \(format(high))"
            case (nil, nil):
                return nil
            }
        }

        private static func symbol(for currency: String) -> String {
            switch currency.uppercased() {
            case "USD": return "$"
            case "GBP": return "£"
            case "EUR": return "€"
            case "JPY": return "¥"
            default: return currency.uppercased() + " "
            }
        }
    }
}

extension Attributed where Value == String {
    /// Drops fields the model filled in with an empty string, which otherwise render as a
    /// heading with nothing underneath it.
    var nilIfBlank: Attributed<String>? {
        isMeaningful ? self : nil
    }
}

extension WineDossier {
    public var displayTitle: String { identity.displayTitle }

    public var displaySubtitle: String? {
        var parts: [String] = []
        if identity.vintage != nil || identity.isNonVintage { parts.append(identity.vintageText) }
        if let appellation = origin.appellation?.value {
            parts.append(appellation)
        } else if let region = origin.region?.value {
            parts.append(region)
        }
        parts.append(identity.wineType.displayName)
        return parts.removingDuplicatesCaseInsensitively().joined(separator: " · ").nilIfBlank
    }

    /// Serving temperature from the sources when there is one, otherwise the convention for
    /// the style. Better a sensible default than an empty row.
    public var servingTemperature: (range: ClosedRangeBox, isConventional: Bool) {
        if let stated = drinkingWindow.servingTemperatureCelsius {
            return (stated, false)
        }
        return (identity.wineType.conventionalServingTemperature, true)
    }

    /// Citations no field points at. Shown under "Also consulted" so a source is never
    /// silently dropped from the page.
    public var unreferencedSources: [Citation] {
        let referenced = Set(referencedSourceIndices)
        return sources.enumerated()
            .filter { !referenced.contains($0.offset) }
            .map(\.element)
    }

    private var referencedSourceIndices: [Int] {
        var indices: [Int] = []
        let attributedStrings: [Attributed<String>?] = [
            origin.country, origin.region, origin.subregion, origin.appellation,
            origin.vineyard, origin.classification, origin.terroirNotes,
            winemaking.winemakerNotes, winemaking.vinification, winemaking.aging,
            winemaking.viticulture, winemaking.productionQuantity,
            tasting.nose, tasting.palate, tasting.finish
        ]
        indices.append(contentsOf: attributedStrings.compactMap { $0 }.flatMap(\.sourceIndices))
        indices.append(contentsOf: drinkingWindow.sourceIndices)
        indices.append(contentsOf: priceEstimate?.sourceIndices ?? [])
        indices.append(contentsOf: ratings.compactMap(\.sourceIndex))
        return indices
    }
}
