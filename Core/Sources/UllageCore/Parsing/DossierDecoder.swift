import Foundation

/// Turns the assistant's text into typed values.
///
/// Strict schema mode means the text should be exactly one JSON object, but "should" is doing
/// a lot of work in a sentence about language models. Some models fence the JSON in
/// backticks, some prepend a line of chat, and a truncated stream leaves the object unclosed.
/// Recovering from the first two is cheap and worth doing; the third is reported honestly.
public enum ModelOutputDecoder {
    public static func decodeLabelReading(from text: String) throws -> LabelReading {
        try decode(LabelReading.self, from: text)
    }

    public static func decodeDossier(from text: String) throws -> WineDossier {
        try decode(WineDossier.self, from: text)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let json = extractJSONObject(from: text) else {
            throw ResponsesError.malformedJSON(
                underlying: "No JSON object was found in the reply.",
                excerpt: String(text.prefix(400))
            )
        }
        guard let data = json.data(using: .utf8) else {
            throw ResponsesError.malformedJSON(
                underlying: "The reply was not valid UTF-8.",
                excerpt: String(text.prefix(400))
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ResponsesError.malformedJSON(
                underlying: readableDescription(of: error),
                excerpt: String(json.prefix(400))
            )
        }
    }

    /// Pulls the first complete JSON object out of a block of text.
    ///
    /// Scans for balanced braces while tracking string literals and escapes, so a `}` inside a
    /// tasting note does not end the object early. Returns nil if no object ever closes, which
    /// is the signal that the response was cut off.
    public static func extractJSONObject(from text: String) -> String? {
        let stripped = strippingCodeFence(text)
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in stripped.indices {
            let character = stripped[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let start {
                    return String(stripped[start...index])
                }
            default:
                break
            }
        }
        return nil
    }

    private static func strippingCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// `DecodingError`'s own description is a wall of context objects. This keeps the part a
    /// person can act on, which is the key path and what was wrong with it.
    private static func readableDescription(of error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue).filter { !$0.isEmpty }
            return keys.isEmpty ? "the root object" : keys.joined(separator: ".")
        }
        switch decodingError {
        case let .keyNotFound(key, context):
            return "Missing '\(key.stringValue)' in \(path(context))."
        case let .typeMismatch(type, context):
            return "Expected \(type) at \(path(context))."
        case let .valueNotFound(type, context):
            return "Missing value of type \(type) at \(path(context))."
        case let .dataCorrupted(context):
            return "Malformed JSON at \(path(context)). \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}

extension WineDossier {
    /// Folds the response's own citation annotations into the dossier.
    ///
    /// The model is asked to fill in `sources` itself, but when it forgets, the API's
    /// `url_citation` annotations record the pages it actually opened. Falling back to those
    /// keeps the sources list honest rather than empty.
    public func mergingAnnotatedSources(_ annotated: [Citation]) -> WineDossier {
        guard !annotated.isEmpty else { return self }
        var copy = self
        var known = Set(sources.map(\.url))
        for citation in annotated where known.insert(citation.url).inserted {
            copy.sources.append(citation)
        }
        return copy
    }
}
