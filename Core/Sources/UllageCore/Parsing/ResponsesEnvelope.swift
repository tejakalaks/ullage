import Foundation

/// The parts of a non-streamed Responses API reply that matter to us.
///
/// The full payload is large and mostly irrelevant. What we need is the assistant's text
/// (which under a strict schema is the dossier JSON), the searches it ran, any URLs it cited,
/// and whether it stopped early — a refusal or a truncated response has to be surfaced as
/// itself rather than as a JSON parse failure.
public struct ResponsesEnvelope: Decodable, Sendable {
    public var id: String?
    public var status: String?
    public var model: String?
    public var outputText: String
    public var refusal: String?
    public var incompleteReason: String?
    public var searchQueries: [String]
    public var annotatedURLs: [Citation]
    public var usage: Usage?

    public struct Usage: Decodable, Sendable, Hashable {
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var totalTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, model, output, usage
        case incompleteDetails = "incomplete_details"
        case error
    }

    public init(
        id: String? = nil,
        status: String? = nil,
        model: String? = nil,
        outputText: String,
        refusal: String? = nil,
        incompleteReason: String? = nil,
        searchQueries: [String] = [],
        annotatedURLs: [Citation] = [],
        usage: Usage? = nil
    ) {
        self.id = id
        self.status = status
        self.model = model
        self.outputText = outputText
        self.refusal = refusal
        self.incompleteReason = incompleteReason
        self.searchQueries = searchQueries
        self.annotatedURLs = annotatedURLs
        self.usage = usage
    }

    private struct IncompleteDetails: Decodable {
        var reason: String?
    }

    private struct APIErrorBody: Decodable {
        var message: String?
        var code: String?
    }

    private struct OutputItem: Decodable {
        var type: String?
        var content: [ContentPart]?
        var action: SearchAction?
        var status: String?
    }

    private struct SearchAction: Decodable {
        var query: String?
        var type: String?
    }

    private struct ContentPart: Decodable {
        var type: String?
        var text: String?
        var refusal: String?
        var annotations: [Annotation]?
    }

    private struct Annotation: Decodable {
        var type: String?
        var url: String?
        var title: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, .id)
        status = c.lenient(String.self, .status)
        model = c.lenient(String.self, .model)
        usage = c.lenient(Usage.self, .usage)
        incompleteReason = c.lenient(IncompleteDetails.self, .incompleteDetails)?.reason
        let items = c.lenient([OutputItem].self, .output, default: [])

        var text = ""
        var refusalText: String?
        var queries: [String] = []
        var citations: [Citation] = []

        for item in items {
            if item.type == "web_search_call", let query = item.action?.query?.nilIfBlank {
                queries.append(query)
            }
            for part in item.content ?? [] {
                if let partText = part.text {
                    text += partText
                }
                if let partRefusal = part.refusal?.nilIfBlank {
                    refusalText = (refusalText.map { $0 + "\n" } ?? "") + partRefusal
                }
                for annotation in part.annotations ?? [] where annotation.type == "url_citation" {
                    guard let url = annotation.url?.nilIfBlank else { continue }
                    citations.append(Citation(title: annotation.title?.nilIfBlank ?? url, url: url))
                }
            }
        }

        outputText = text
        refusal = refusalText
        searchQueries = queries
        // The same page is often cited for several sentences.
        var seenURLs = Set<String>()
        annotatedURLs = citations.filter { seenURLs.insert($0.url).inserted }

        if let apiError = c.lenient(APIErrorBody.self, .error), let message = apiError.message {
            throw ResponsesError.api(message: message, code: apiError.code)
        }
    }
}

public enum ResponsesError: LocalizedError, Sendable {
    case api(message: String, code: String?)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case refused(String)
    case incomplete(reason: String?)
    case emptyOutput
    case malformedJSON(underlying: String, excerpt: String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .api(message, _):
            return message
        case .unauthorized:
            return "Your OpenAI API key was rejected. Check it in Settings."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                return "OpenAI is rate limiting this key. Try again in \(Int(retryAfter.rounded()))s."
            }
            return "OpenAI is rate limiting this key. Try again shortly."
        case let .refused(reason):
            return reason
        case let .incomplete(reason):
            return reason.map { "The model stopped early (\($0))." }
                ?? "The model stopped before finishing."
        case .emptyOutput:
            return "The model returned nothing to read."
        case let .malformedJSON(underlying, _):
            return "The model's reply could not be read as a dossier. \(underlying)"
        case let .transport(message):
            return message
        }
    }

    /// Whether retrying the identical request could plausibly work.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .transport, .malformedJSON, .emptyOutput, .incomplete:
            return true
        case .unauthorized, .refused, .api:
            return false
        }
    }
}
