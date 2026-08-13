import Foundation

/// Helpers for building JSON Schema that satisfies OpenAI structured-output strict mode.
///
/// Strict mode has two rules that are easy to break by hand and produce an opaque 400 when
/// you do: every object must set `additionalProperties: false` and list *every* property in
/// `required`. Optionality is therefore expressed as a nullable type rather than by omitting
/// the key. These helpers make that the only way to build a node, and `SchemaValidator`
/// checks the finished tree in a unit test.
public enum Schema {
    public static func object(
        _ description: String? = nil,
        _ properties: [(String, JSONValue)]
    ) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("type", .string("object"))]
        if let description {
            pairs.append(("description", .string(description)))
        }
        pairs.append(("properties", .object(properties.map { (key: $0.0, value: $0.1) })))
        pairs.append(("required", .array(properties.map { .string($0.0) })))
        pairs.append(("additionalProperties", .bool(false)))
        return .object(pairs)
    }

    public static func string(_ description: String? = nil) -> JSONValue {
        scalar("string", description)
    }

    public static func number(_ description: String? = nil) -> JSONValue {
        scalar("number", description)
    }

    public static func integer(_ description: String? = nil) -> JSONValue {
        scalar("integer", description)
    }

    public static func boolean(_ description: String? = nil) -> JSONValue {
        scalar("boolean", description)
    }

    public static func stringEnum(_ cases: [String], _ description: String? = nil) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("type", .string("string"))]
        if let description {
            pairs.append(("description", .string(description)))
        }
        pairs.append(("enum", .array(cases.map { .string($0) })))
        return .object(pairs)
    }

    public static func array(of element: JSONValue, _ description: String? = nil) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("type", .string("array"))]
        if let description {
            pairs.append(("description", .string(description)))
        }
        pairs.append(("items", element))
        return .object(pairs)
    }

    /// Makes a node accept `null` as well as its own type, which is how an optional field is
    /// spelled under strict mode.
    public static func nullable(_ node: JSONValue) -> JSONValue {
        guard let pairs = node.objectPairs else { return node }
        return .object(pairs.map { pair in
            guard pair.key == "type" else { return pair }
            switch pair.value {
            case let .string(type) where type != "null":
                return (key: "type", value: .array([.string(type), .string("null")]))
            case let .array(types) where !types.contains(.string("null")):
                return (key: "type", value: .array(types + [.string("null")]))
            default:
                return pair
            }
        })
    }

    private static func scalar(_ type: String, _ description: String?) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("type", .string(type))]
        if let description {
            pairs.append(("description", .string(description)))
        }
        return .object(pairs)
    }
}

/// Checks a schema against the strict-mode rules, so a malformed schema fails in a unit test
/// with a precise path instead of as a 400 from the API at scan time.
public enum SchemaValidator {
    public struct Violation: Hashable, CustomStringConvertible {
        public var path: String
        public var problem: String

        public var description: String { "\(path): \(problem)" }
    }

    public static func violations(in schema: JSONValue, path: String = "#") -> [Violation] {
        guard let pairs = schema.objectPairs else { return [] }
        var found: [Violation] = []
        let typeValue = schema["type"]
        let isObject = typeValue == .string("object")
            || (typeValue?.arrayValue?.contains(.string("object")) ?? false)

        if isObject {
            if schema["additionalProperties"] != .bool(false) {
                found.append(Violation(path: path, problem: "object must set additionalProperties to false"))
            }
            let properties = schema["properties"]?.objectPairs ?? []
            let required = Set((schema["required"]?.arrayValue ?? []).compactMap(\.stringValue))
            let declared = Set(properties.map(\.key))
            for missing in declared.subtracting(required).sorted() {
                found.append(Violation(path: "\(path)/\(missing)", problem: "property is not listed in required"))
            }
            for extra in required.subtracting(declared).sorted() {
                found.append(Violation(path: "\(path)/\(extra)", problem: "required names a property that does not exist"))
            }
            for (key, value) in properties {
                found.append(contentsOf: violations(in: value, path: "\(path)/\(key)"))
            }
        }

        if let items = schema["items"] {
            found.append(contentsOf: violations(in: items, path: "\(path)[]"))
        }

        // Keywords strict mode rejects. Constraints like these belong in `description`, where
        // the model will actually act on them.
        for unsupported in ["minimum", "maximum", "minLength", "maxLength", "pattern", "format", "minItems", "maxItems"] {
            if pairs.contains(where: { $0.key == unsupported }) {
                found.append(Violation(path: path, problem: "unsupported keyword '\(unsupported)' for strict mode"))
            }
        }

        return found
    }
}
