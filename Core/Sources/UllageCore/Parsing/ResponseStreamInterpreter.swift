import Foundation

/// A meaningful thing that happened during a streamed response.
public enum ResponseStreamEvent: Sendable {
    /// More assistant text arrived. Under a strict schema this is a slice of the dossier JSON.
    case textDelta(String)
    /// The model started a web search. The query is the interesting part: it is what turns a
    /// spinner into a readable account of what the model is doing on the user's behalf.
    case searchStarted(query: String?)
    case searchCompleted(query: String?)
    /// A summary of the model's reasoning, when the model emits one.
    case reasoningSummary(String)
    /// The response finished; the payload carries the final text and citations.
    case completed(ResponsesEnvelope)
    case failed(ResponsesError)
}

/// Turns raw SSE messages into `ResponseStreamEvent`s.
///
/// Search queries arrive on `response.output_item.added` but completion arrives on
/// `response.web_search_call.completed`, which carries only an item id, so the interpreter
/// remembers which query belongs to which item to keep the research log coherent.
public struct ResponseStreamInterpreter: Sendable {
    private var queriesByItemID: [String: String] = [:]
    private var accumulatedText = ""

    public init() {}

    public var text: String { accumulatedText }

    private struct EventPayload: Decodable {
        var delta: String?
        var text: String?
        var item_id: String?
        var item: Item?
        var response: ResponsesEnvelope?
        var error: ErrorBody?
        var summary_text: String?

        struct Item: Decodable {
            var id: String?
            var type: String?
            var action: Action?
            struct Action: Decodable {
                var query: String?
            }
        }

        struct ErrorBody: Decodable {
            var message: String?
            var code: String?
        }
    }

    public mutating func interpret(_ message: SSEMessage) -> ResponseStreamEvent? {
        // The Responses API repeats the event name inside the payload, but the SSE `event:`
        // field is authoritative and cheaper to read.
        guard let name = message.event ?? typeField(in: message.data) else { return nil }

        if message.data == "[DONE]" { return nil }

        let payload = decodePayload(message.data)

        switch name {
        case "response.output_text.delta":
            guard let delta = payload?.delta, !delta.isEmpty else { return nil }
            accumulatedText += delta
            return .textDelta(delta)

        case "response.output_item.added":
            guard let item = payload?.item, item.type == "web_search_call" else { return nil }
            let query = item.action?.query?.nilIfBlank
            if let id = item.id, let query {
                queriesByItemID[id] = query
            }
            return .searchStarted(query: query)

        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            // Only worth reporting if it carries a query we have not already announced.
            guard let id = payload?.item_id, queriesByItemID[id] == nil else { return nil }
            return .searchStarted(query: nil)

        case "response.web_search_call.completed":
            let query = payload?.item_id.flatMap { queriesByItemID[$0] }
            return .searchCompleted(query: query)

        case "response.reasoning_summary_text.delta":
            guard let delta = payload?.delta?.nilIfBlank else { return nil }
            return .reasoningSummary(delta)

        case "response.completed":
            guard let envelope = payload?.response else { return nil }
            return .completed(envelope)

        case "response.incomplete":
            return .failed(.incomplete(reason: payload?.response?.incompleteReason))

        case "response.failed":
            let message = payload?.response?.status ?? payload?.error?.message ?? "The response failed."
            return .failed(.api(message: message, code: payload?.error?.code))

        case "error":
            let message = payload?.error?.message ?? "The stream reported an error."
            return .failed(.api(message: message, code: payload?.error?.code))

        default:
            return nil
        }
    }

    /// The assistant text accumulated so far. Used when a stream ends without a
    /// `response.completed`, which happens if the connection drops late.
    public func finalTextOrNil() -> String? {
        accumulatedText.nilIfBlank
    }

    private func decodePayload(_ data: String) -> EventPayload? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EventPayload.self, from: raw)
    }

    private func typeField(in data: String) -> String? {
        struct TypeOnly: Decodable { var type: String? }
        guard let raw = data.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(TypeOnly.self, from: raw))?.type
    }
}
