import Foundation

/// Builds Responses API request bodies.
///
/// Kept in the core, away from `URLSession`, so the exact JSON sent for a scan can be asserted
/// in a test rather than discovered from a 400 on a phone.
public enum ResponsesRequest {
    /// One image, already encoded as a data URL.
    public struct ImagePayload: Hashable, Sendable {
        public var dataURL: String
        /// "front label", "back label" — telling the model which is which measurably improves
        /// how it reads the back-label small print.
        public var role: String?

        public init(dataURL: String, role: String? = nil) {
            self.dataURL = dataURL
            self.role = role
        }
    }

    public struct Options: Hashable, Sendable {
        public var model: String
        public var enableWebSearch: Bool
        /// Passed straight through as `reasoning.effort`; nil omits the field entirely for
        /// models that do not accept it.
        public var reasoningEffort: String?
        public var maxOutputTokens: Int?

        public init(
            model: String,
            enableWebSearch: Bool,
            reasoningEffort: String? = nil,
            maxOutputTokens: Int? = nil
        ) {
            self.model = model
            self.enableWebSearch = enableWebSearch
            self.reasoningEffort = reasoningEffort
            self.maxOutputTokens = maxOutputTokens
        }
    }

    /// Stage A: images in, label reading out. No tools — this pass is about the photograph.
    public static func labelReading(
        images: [ImagePayload],
        options: Options,
        stream: Bool
    ) -> JSONValue {
        var instructions = StagePrompts.labelIdentification
        if images.count > 1 {
            instructions += "\n\n" + StagePrompts.multiImageNote
        }

        var content: [JSONValue] = []
        for image in images {
            if let role = image.role {
                content.append(.object([
                    ("type", .string("input_text")),
                    ("text", .string("This photograph is the \(role)."))
                ]))
            }
            content.append(.object([
                ("type", .string("input_image")),
                ("image_url", .string(image.dataURL)),
                ("detail", .string("high"))
            ]))
        }
        content.append(.object([
            ("type", .string("input_text")),
            ("text", .string("Identify this wine from the photograph(s)."))
        ]))

        return body(
            options: options,
            instructions: instructions,
            userContent: content,
            schemaName: WineSchema.labelReadingName,
            schema: WineSchema.labelReading,
            useWebSearch: false,
            stream: stream
        )
    }

    /// Stage B: the reading plus the label images, researched against the web.
    ///
    /// The images are sent again on purpose. If the research turns up something that
    /// contradicts stage A — a cuvée that does not exist, a vintage the estate did not
    /// declare — the model can look at the bottle again instead of committing to the error.
    public static func research(
        prompt: String,
        images: [ImagePayload],
        options: Options,
        stream: Bool
    ) -> JSONValue {
        var content: [JSONValue] = [
            .object([
                ("type", .string("input_text")),
                ("text", .string(prompt))
            ])
        ]
        for image in images {
            content.append(.object([
                ("type", .string("input_image")),
                ("image_url", .string(image.dataURL)),
                ("detail", .string("low"))
            ]))
        }

        return body(
            options: options,
            instructions: StagePrompts.research,
            userContent: content,
            schemaName: WineSchema.dossierName,
            schema: WineSchema.dossier,
            useWebSearch: options.enableWebSearch,
            stream: stream
        )
    }

    private static func body(
        options: Options,
        instructions: String,
        userContent: [JSONValue],
        schemaName: String,
        schema: JSONValue,
        useWebSearch: Bool,
        stream: Bool
    ) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("model", .string(options.model)),
            ("instructions", .string(instructions)),
            ("input", .array([
                .object([
                    ("role", .string("user")),
                    ("content", .array(userContent))
                ])
            ]))
        ]

        if useWebSearch {
            pairs.append(("tools", .array([
                .object([("type", .string("web_search"))])
            ])))
            pairs.append(("tool_choice", .string("auto")))
        }

        pairs.append(("text", .object([
            ("format", .object([
                ("type", .string("json_schema")),
                ("name", .string(schemaName)),
                ("strict", .bool(true)),
                ("schema", schema)
            ]))
        ])))

        if let effort = options.reasoningEffort {
            pairs.append(("reasoning", .object([("effort", .string(effort))])))
        }
        if let maxOutputTokens = options.maxOutputTokens {
            pairs.append(("max_output_tokens", .integer(maxOutputTokens)))
        }
        // Storing responses server-side is off by default here: label photographs are the
        // user's, and there is no reason for them to persist in someone's dashboard.
        pairs.append(("store", .bool(false)))
        pairs.append(("stream", .bool(stream)))

        return .object(pairs)
    }
}
