import Foundation

/// A JSON value that keeps object keys in the order they were written.
///
/// Ordering matters here for two reasons: a JSON schema reads far better in a diff when its
/// keys stay put, and request bodies stay byte-stable between runs, which makes recorded
/// fixtures meaningful.
public enum JSONValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case null

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.integer(a), .integer(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case (.null, .null): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .string(v): hasher.combine(0); hasher.combine(v)
        case let .number(v): hasher.combine(1); hasher.combine(v)
        case let .integer(v): hasher.combine(2); hasher.combine(v)
        case let .bool(v): hasher.combine(3); hasher.combine(v)
        case let .array(v): hasher.combine(4); hasher.combine(v)
        case let .object(v):
            hasher.combine(5)
            for (key, value) in v {
                hasher.combine(key)
                hasher.combine(value)
            }
        case .null: hasher.combine(6)
        }
    }
}

extension JSONValue {
    public subscript(key: String) -> JSONValue? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(values) = self else { return nil }
        return values
    }

    public var objectPairs: [(key: String, value: JSONValue)]? {
        guard case let .object(pairs) = self else { return nil }
        return pairs
    }

    /// Serialises to JSON with object keys in the order they were written.
    ///
    /// Written by hand rather than handed to `JSONEncoder`, which backs keyed containers with
    /// a dictionary and so emits keys in an arbitrary order. That would scramble the schema on
    /// every run and make request bodies impossible to compare between builds.
    public func encodedString(prettyPrinted: Bool = false) -> String {
        var output = ""
        write(to: &output, indent: prettyPrinted ? 0 : nil)
        return output
    }

    public func encodedData(prettyPrinted: Bool = false) -> Data {
        Data(encodedString(prettyPrinted: prettyPrinted).utf8)
    }

    private func write(to output: inout String, indent: Int?) {
        let newline = indent == nil ? "" : "\n"
        let pad = indent.map { String(repeating: "  ", count: $0 + 1) } ?? ""
        let closingPad = indent.map { String(repeating: "  ", count: $0) } ?? ""
        let separator = indent == nil ? ":" : ": "

        switch self {
        case let .string(value):
            output += Self.quote(value)
        case let .integer(value):
            output += String(value)
        case let .number(value):
            // JSON has no way to say infinity or NaN; null is the honest encoding.
            output += value.isFinite ? String(value) : "null"
        case let .bool(value):
            output += value ? "true" : "false"
        case .null:
            output += "null"
        case let .array(values):
            guard !values.isEmpty else {
                output += "[]"
                return
            }
            output += "[" + newline
            for (offset, value) in values.enumerated() {
                output += pad
                value.write(to: &output, indent: indent.map { $0 + 1 })
                if offset < values.count - 1 { output += "," }
                output += newline
            }
            output += closingPad + "]"
        case let .object(pairs):
            guard !pairs.isEmpty else {
                output += "{}"
                return
            }
            output += "{" + newline
            for (offset, pair) in pairs.enumerated() {
                output += pad + Self.quote(pair.key) + separator
                pair.value.write(to: &output, indent: indent.map { $0 + 1 })
                if offset < pairs.count - 1 { output += "," }
                output += newline
            }
            output += closingPad + "}"
        }
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .integer(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
