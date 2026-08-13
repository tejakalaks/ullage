import Foundation

/// Where a piece of information in a dossier came from.
///
/// The whole point of showing this in the UI is honesty: a drinking window printed on
/// the producer's tech sheet and one the model guessed from the region and vintage are
/// very different claims, and they should not look identical to the person deciding
/// whether to open the bottle tonight.
public enum Provenance: String, Codable, Hashable, Sendable, CaseIterable {
    /// Read directly off the photographed label.
    case label
    /// Found on the web during research; the supporting source is in `Attributed.sources`.
    case web
    /// Neither on the label nor found online — the model's own inference.
    case inference

    public var shortLabel: String {
        switch self {
        case .label: return "On label"
        case .web: return "Sourced"
        case .inference: return "Inferred"
        }
    }

    public var explanation: String {
        switch self {
        case .label: return "Read directly from the bottle label."
        case .web: return "Found in a source online."
        case .inference: return "Estimated by the model, not found on the label or online."
        }
    }

    /// Rough ordering of how much a claim should be trusted, weakest first.
    public var trustRank: Int {
        switch self {
        case .inference: return 0
        case .web: return 1
        case .label: return 2
        }
    }
}

/// A value carrying its own provenance and supporting sources.
///
/// Sources are stored as indices into `WineDossier.sources` so a single citation can back
/// many fields without being duplicated all over the payload — which also keeps the JSON
/// the model has to emit substantially smaller.
public struct Attributed<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value
    public var provenance: Provenance
    /// Indices into `WineDossier.sources`. May be empty even for `.web` if the model omitted them.
    public var sourceIndices: [Int]

    public init(value: Value, provenance: Provenance = .inference, sourceIndices: [Int] = []) {
        self.value = value
        self.provenance = provenance
        self.sourceIndices = sourceIndices
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case provenance
        case sourceIndices = "source_indices"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Value.self, forKey: .value)
        // Models occasionally invent provenance strings; an unrecognised one is treated as
        // an inference rather than failing the whole decode.
        provenance = (try? container.decode(Provenance.self, forKey: .provenance)) ?? .inference
        sourceIndices = (try? container.decodeIfPresent([Int].self, forKey: .sourceIndices)) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(sourceIndices, forKey: .sourceIndices)
    }
}

extension Attributed {
    /// Resolves this field's citations against a dossier's source list, skipping out-of-range
    /// indices, which models do produce from time to time.
    public func sources(in all: [Citation]) -> [Citation] {
        sourceIndices.compactMap { all.indices.contains($0) ? all[$0] : nil }
    }
}

extension Attributed where Value == String {
    public var isMeaningful: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
