import Foundation

/// One server-sent event: its name and its accumulated data payload.
public struct SSEMessage: Hashable, Sendable {
    public var event: String?
    public var data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental server-sent events parser.
///
/// Line-oriented and free of any networking, so the whole streaming path can be exercised in
/// tests by feeding it a recorded transcript.
public struct SSEParser: Sendable {
    private var eventName: String?
    private var dataLines: [String] = []

    public init() {}

    /// Feeds one line, without its newline. Returns a message when the line completes one.
    public mutating func consume(line: String) -> SSEMessage? {
        // A blank line terminates the current event.
        if line.isEmpty {
            return flush()
        }
        // Comments and heartbeats.
        if line.hasPrefix(":") {
            return nil
        }
        guard let colon = line.firstIndex(of: ":") else {
            // A bare field name with no value is legal and carries an empty value.
            appendField(name: line, value: "")
            return nil
        }
        let name = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        appendField(name: name, value: value)
        return nil
    }

    /// Emits any event left buffered when the stream ends without a trailing blank line.
    public mutating func finish() -> SSEMessage? {
        flush()
    }

    private mutating func appendField(name: String, value: String) {
        switch name {
        case "event": eventName = value
        case "data": dataLines.append(value)
        default: break // `id` and `retry` are not meaningful for this API.
        }
    }

    private mutating func flush() -> SSEMessage? {
        defer {
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
        }
        guard !dataLines.isEmpty || eventName != nil else { return nil }
        return SSEMessage(event: eventName, data: dataLines.joined(separator: "\n"))
    }

    /// Parses a complete transcript in one go.
    public static func messages(in transcript: String) -> [SSEMessage] {
        var parser = SSEParser()
        var messages: [SSEMessage] = []
        for line in splitIntoLines(transcript) {
            if let message = parser.consume(line: line) {
                messages.append(message)
            }
        }
        if let message = parser.finish() {
            messages.append(message)
        }
        return messages
    }

    /// Splits on any line ending.
    ///
    /// Splitting on `"\n"` alone is not enough: Swift treats CRLF as a single `Character`, so a
    /// transcript delivered with Windows line endings looks like one enormous line. Working in
    /// unicode scalars sidesteps the grapheme clustering entirely.
    static func splitIntoLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\r" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
                // Consume the paired newline of a CRLF.
                if index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 1
                }
            } else if scalar == "\n" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
            index += 1
        }
        lines.append(String(current))
        return lines
    }
}
