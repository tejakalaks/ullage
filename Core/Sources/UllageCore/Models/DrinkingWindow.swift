import Foundation

/// When the bottle is worth opening.
///
/// Only the years are stored. `status(asOf:)` is computed on demand rather than baked in at
/// scan time, so a bottle scanned in 2026 and revisited in 2031 reports where it actually is
/// in its life instead of what the model said five years ago.
public struct DrinkingWindow: Codable, Hashable, Sendable {
    public var startYear: Int?
    public var endYear: Int?
    /// The sweet spot inside the wider window, if the sources are specific about one.
    public var peakStartYear: Int?
    public var peakEndYear: Int?
    /// Free text such as "decant 1 hour" or "no hurry, but the fruit is fading".
    public var advice: String?
    public var decantMinutes: Int?
    public var servingTemperatureCelsius: ClosedRangeBox?
    public var provenance: Provenance
    public var sourceIndices: [Int]

    public init(
        startYear: Int? = nil,
        endYear: Int? = nil,
        peakStartYear: Int? = nil,
        peakEndYear: Int? = nil,
        advice: String? = nil,
        decantMinutes: Int? = nil,
        servingTemperatureCelsius: ClosedRangeBox? = nil,
        provenance: Provenance = .inference,
        sourceIndices: [Int] = []
    ) {
        self.startYear = startYear
        self.endYear = endYear
        self.peakStartYear = peakStartYear
        self.peakEndYear = peakEndYear
        self.advice = advice
        self.decantMinutes = decantMinutes
        self.servingTemperatureCelsius = servingTemperatureCelsius
        self.provenance = provenance
        self.sourceIndices = sourceIndices
    }

    private enum CodingKeys: String, CodingKey {
        case startYear = "start_year"
        case endYear = "end_year"
        case peakStartYear = "peak_start_year"
        case peakEndYear = "peak_end_year"
        case advice
        case decantMinutes = "decant_minutes"
        case servingTemperatureCelsius = "serving_temperature_celsius"
        case provenance
        case sourceIndices = "source_indices"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startYear = try c.decodeIfPresent(Int.self, forKey: .startYear)
        endYear = try c.decodeIfPresent(Int.self, forKey: .endYear)
        peakStartYear = try c.decodeIfPresent(Int.self, forKey: .peakStartYear)
        peakEndYear = try c.decodeIfPresent(Int.self, forKey: .peakEndYear)
        advice = try c.decodeIfPresent(String.self, forKey: .advice)
        decantMinutes = try c.decodeIfPresent(Int.self, forKey: .decantMinutes)
        servingTemperatureCelsius = try c.decodeIfPresent(ClosedRangeBox.self, forKey: .servingTemperatureCelsius)
        provenance = (try? c.decode(Provenance.self, forKey: .provenance)) ?? .inference
        sourceIndices = (try? c.decodeIfPresent([Int].self, forKey: .sourceIndices)) ?? []
    }

    public var isEmpty: Bool {
        startYear == nil && endYear == nil && peakStartYear == nil && peakEndYear == nil
            && (advice?.isEmpty ?? true)
    }

    public enum Status: String, Codable, Hashable, Sendable {
        case tooYoung
        case drinkable
        case atPeak
        case fading
        case pastWindow
        case unknown

        public var headline: String {
            switch self {
            case .tooYoung: return "Too young"
            case .drinkable: return "Ready to drink"
            case .atPeak: return "At its peak"
            case .fading: return "Drink up"
            case .pastWindow: return "Past its window"
            case .unknown: return "Window unknown"
            }
        }
    }

    /// Where the bottle sits in its window in the given year.
    ///
    /// `fading` is the last year of the window, where "there is no rush" stops being true.
    public func status(asOf year: Int) -> Status {
        if let peakStart = peakStartYear, let peakEnd = peakEndYear,
           year >= peakStart, year <= peakEnd {
            return .atPeak
        }
        if let start = startYear, year < start { return .tooYoung }
        if let end = endYear, year > end { return .pastWindow }
        if let end = endYear, year == end { return .fading }
        if startYear != nil || endYear != nil { return .drinkable }
        return .unknown
    }

    public func status(asOf date: Date = Date(), calendar: Calendar = .current) -> Status {
        status(asOf: calendar.component(.year, from: date))
    }

    /// Fractional position through the window, for drawing a progress marker.
    /// `nil` when the window is open-ended or missing, since a marker would be a lie.
    public func progress(asOf year: Int) -> Double? {
        guard let start = startYear, let end = endYear, end > start else { return nil }
        let clamped = min(max(year, start), end)
        return Double(clamped - start) / Double(end - start)
    }

    public func progress(asOf date: Date = Date(), calendar: Calendar = .current) -> Double? {
        progress(asOf: calendar.component(.year, from: date))
    }

    /// Human-readable span, e.g. "2024 – 2038", "from 2027", "through 2029".
    public var yearRangeDescription: String? {
        switch (startYear, endYear) {
        case let (start?, end?): return "\(start) – \(end)"
        case let (start?, nil): return "from \(start)"
        case let (nil, end?): return "through \(end)"
        case (nil, nil): return nil
        }
    }

    public var peakRangeDescription: String? {
        switch (peakStartYear, peakEndYear) {
        case let (start?, end?): return start == end ? "\(start)" : "\(start) – \(end)"
        case let (start?, nil): return "from \(start)"
        case let (nil, end?): return "through \(end)"
        case (nil, nil): return nil
        }
    }
}

/// A numeric range that survives a round trip through JSON.
///
/// `ClosedRange` encodes as an unlabelled array, which is awkward to describe in a JSON
/// schema and easy for a model to get wrong, so serving temperatures use explicit bounds.
public struct ClosedRangeBox: Codable, Hashable, Sendable {
    public var lower: Double
    public var upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
    }

    private enum CodingKeys: String, CodingKey {
        case lower
        case upper
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let l = try c.decode(Double.self, forKey: .lower)
        let u = try c.decode(Double.self, forKey: .upper)
        self.init(lower: l, upper: u)
    }

    public func formatted(unit: String = "°C") -> String {
        let format: (Double) -> String = { value in
            value == value.rounded()
                ? String(Int(value))
                : String(format: "%.1f", value)
        }
        return lower == upper
            ? "\(format(lower))\(unit)"
            : "\(format(lower))–\(format(upper))\(unit)"
    }
}
