import Foundation
import UllageCore

/// A thin client for the OpenAI Responses API.
///
/// Deliberately small: it knows how to send a body, how to read a stream, and how to turn an
/// HTTP failure into an error a person can act on. Everything about *what* to send lives in
/// `UllageCore`, where it can be tested without a network.
struct ResponsesClient {
    var apiKey: String
    var session: URLSession
    var baseURL: URL

    init(
        apiKey: String,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!
    ) {
        self.apiKey = apiKey
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - Non-streaming

    func send(_ body: JSONValue) async throws -> ResponsesEnvelope {
        let request = makeRequest(path: "responses", body: body.encodedData())
        let (data, response) = try await perform(request)
        try Self.validate(response: response, data: data)
        do {
            return try JSONDecoder().decode(ResponsesEnvelope.self, from: data)
        } catch let error as ResponsesError {
            throw error
        } catch {
            throw ResponsesError.malformedJSON(
                underlying: error.localizedDescription,
                excerpt: String(decoding: data.prefix(400), as: UTF8.self)
            )
        }
    }

    // MARK: - Streaming

    /// Streams a response, yielding events as they arrive.
    ///
    /// The stream is what makes the research pass feel like something is happening rather than
    /// a two-minute spinner: each search the model runs is surfaced as it starts.
    func stream(_ body: JSONValue) -> AsyncThrowingStream<ResponseStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = makeRequest(path: "responses", body: body.encodedData(), streaming: true)
                    let (bytes, response) = try await session.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        // An error response is JSON, not an event stream; collect and report it.
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        try Self.validate(response: response, data: data)
                    }

                    var parser = SSEParser()
                    var interpreter = ResponseStreamInterpreter()
                    var sawTerminalEvent = false

                    func handle(_ message: SSEMessage) {
                        guard let event = interpreter.interpret(message) else { return }
                        switch event {
                        case .completed, .failed: sawTerminalEvent = true
                        default: break
                        }
                        continuation.yield(event)
                    }

                    // Split the byte stream by hand rather than using `bytes.lines`, which
                    // discards empty lines — and an empty line is precisely how SSE marks the
                    // end of an event.
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        guard byte == UInt8(ascii: "\n") else {
                            lineBuffer.append(byte)
                            continue
                        }
                        if lineBuffer.last == UInt8(ascii: "\r") {
                            lineBuffer.removeLast()
                        }
                        let line = String(decoding: lineBuffer, as: UTF8.self)
                        lineBuffer.removeAll(keepingCapacity: true)
                        if let message = parser.consume(line: line) {
                            handle(message)
                        }
                    }
                    if !lineBuffer.isEmpty,
                       let message = parser.consume(line: String(decoding: lineBuffer, as: UTF8.self)) {
                        handle(message)
                    }
                    if let message = parser.finish() {
                        handle(message)
                    }

                    // A stream that stops without a terminal event usually means the connection
                    // dropped. Any text already accumulated may still be a complete dossier, so
                    // it is worth handing back rather than discarding.
                    if !sawTerminalEvent {
                        guard let text = interpreter.finalTextOrNil() else {
                            throw ResponsesError.emptyOutput
                        }
                        continuation.yield(.completed(ResponsesEnvelope(
                            status: "interrupted",
                            outputText: text
                        )))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.friendlyError(from: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Key verification

    /// A cheap authenticated call, used by Settings to check a key before it is saved.
    func verifyKey() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await perform(request)
        try Self.validate(response: response, data: data)
    }

    // MARK: - Plumbing

    private func makeRequest(path: String, body: Data, streaming: Bool = false) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        // Web-grounded research legitimately takes a while; the default 60s cuts it off.
        request.timeoutInterval = streaming ? 300 : 180
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw Self.friendlyError(from: error)
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        let message = APIErrorEnvelope.message(in: data)
        switch http.statusCode {
        case 401, 403:
            throw ResponsesError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "retry-after")).flatMap(TimeInterval.init)
            throw ResponsesError.rateLimited(retryAfter: retryAfter)
        default:
            throw ResponsesError.api(
                message: message ?? "OpenAI returned HTTP \(http.statusCode).",
                code: String(http.statusCode)
            )
        }
    }

    /// Turns `URLError` into something worth reading. "The operation couldn't be completed"
    /// tells a user nothing about what to do next.
    private static func friendlyError(from error: Error) -> Error {
        if error is ResponsesError { return error }
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed:
            return ResponsesError.transport("You appear to be offline. Ullage needs a connection to research a wine.")
        case .timedOut:
            return ResponsesError.transport("The request timed out. The research pass can be slow; try again.")
        case .cancelled:
            return CancellationError()
        default:
            return ResponsesError.transport(urlError.localizedDescription)
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        var message: String?
    }
    var error: Body?

    static func message(in data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error?.message
    }
}