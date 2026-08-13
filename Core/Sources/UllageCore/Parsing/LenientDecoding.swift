import Foundation

/// Forgiving accessors for decoding model output.
///
/// Strict JSON schema makes the shape of a response reliable, but not every provider
/// supports it and a dossier is worth salvaging even when one field arrives malformed.
/// A missing tasting note should not throw away a correct identification.
extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 } ?? fallback
    }

    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)).flatMap { $0 }
    }

    /// Decodes a string, treating empty and whitespace-only values as absent. Models like to
    /// emit `""` or `"unknown"` rather than omitting a field, and those should not reach the UI.
    func lenientString(_ key: Key) -> String? {
        guard let raw = lenient(String.self, key) else { return nil }
        guard let trimmed = raw.nilIfBlank else { return nil }
        let placeholders: Set<String> = ["unknown", "n/a", "na", "none", "not specified", "not available", "null"]
        return placeholders.contains(trimmed.lowercased()) ? nil : trimmed
    }
}
