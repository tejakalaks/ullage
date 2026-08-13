import XCTest
@testable import UllageCore

final class ParsingTests: XCTestCase {
    // MARK: - Envelope

    func testDecodingARecordedResponse() throws {
        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: try Fixture.data("dossier_response.json"))
        XCTAssertEqual(envelope.status, "completed")
        XCTAssertEqual(envelope.searchQueries, ["Domaine Tempier Bandol La Migoua 2019 technical sheet"])
        XCTAssertEqual(envelope.usage?.totalTokens, 3263)
        XCTAssertNil(envelope.refusal)

        // The fixture cites the same page twice, as real responses do for every sentence
        // drawn from one source.
        XCTAssertEqual(envelope.annotatedURLs.count, 1)

        let dossier = try ModelOutputDecoder.decodeDossier(from: envelope.outputText)
        XCTAssertEqual(dossier.identity.producer, "Domaine Tempier")
        XCTAssertEqual(dossier.identity.vintage, 2019)
        XCTAssertEqual(dossier.composition.count, 4)
        XCTAssertEqual(dossier.composition.first?.name, "Mourvedre")
        XCTAssertEqual(dossier.origin.appellation?.value, "Bandol AOC")
        XCTAssertEqual(dossier.origin.appellation?.provenance, .label)
        XCTAssertEqual(dossier.origin.terroirNotes?.sourceIndices, [0])
        XCTAssertEqual(dossier.drinkingWindow.status(asOf: 2030), .atPeak)
        XCTAssertEqual(dossier.ratings.first?.displayScore, "93/100")
        XCTAssertEqual(dossier.priceEstimate?.displayRange, "$65–$85")
    }

    func testNullFieldsBecomeNilRatherThanEmptyStrings() throws {
        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: try Fixture.data("dossier_response.json"))
        let dossier = try ModelOutputDecoder.decodeDossier(from: envelope.outputText)
        XCTAssertNil(dossier.origin.subregion)
        XCTAssertNil(dossier.tasting.palate)
        XCTAssertNil(dossier.winemaking.vinification)
    }

    func testLabelReadingFixture() throws {
        let reading = try ModelOutputDecoder.decodeLabelReading(from: try Fixture.text("label_reading_response.json"))
        XCTAssertTrue(reading.isWineLabel)
        XCTAssertEqual(reading.producer, "Domaine Tempier")
        XCTAssertEqual(reading.displayTitle, "Domaine Tempier La Migoua 2019")
        XCTAssertEqual(reading.displaySubtitle, "Bandol, Provence")
        XCTAssertEqual(reading.suggestedQueries.count, 3)
        XCTAssertTrue(reading.isIdentifiable)
        XCTAssertFalse(reading.confidence.warrantsConfirmation)
        XCTAssertEqual(reading.alternatives.first?.confidence.score ?? 0, 0.12, accuracy: 0.001)
    }

    func testRefusalIsSurfacedAsItself() throws {
        let json = """
        {"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"I can't help with that."}]}]}
        """
        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.refusal, "I can't help with that.")
        XCTAssertTrue(envelope.outputText.isEmpty)
    }

    func testIncompleteResponseCarriesItsReason() throws {
        let json = """
        {"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}
        """
        let envelope = try JSONDecoder().decode(ResponsesEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.incompleteReason, "max_output_tokens")
    }

    // MARK: - Extracting JSON from imperfect replies

    func testExtractingJSONFromACodeFence() throws {
        let text = """
        ```json
        {"is_wine_label": true, "producer": "Château Rayas"}
        ```
        """
        let reading = try ModelOutputDecoder.decodeLabelReading(from: text)
        XCTAssertEqual(reading.producer, "Château Rayas")
    }

    func testExtractingJSONAfterAChattyPreamble() throws {
        let text = """
        Sure! Here is the dossier you asked for:
        {"is_wine_label": true, "producer": "Clos Rougeard"}
        """
        let reading = try ModelOutputDecoder.decodeLabelReading(from: text)
        XCTAssertEqual(reading.producer, "Clos Rougeard")
    }

    /// A closing brace inside a tasting note must not be mistaken for the end of the object.
    func testBracesInsideStringsDoNotTerminateTheObject() throws {
        let text = #"{"is_wine_label": true, "visual_description": "a label reading }{ oddly", "producer": "Envínate"}"#
        let reading = try ModelOutputDecoder.decodeLabelReading(from: text)
        XCTAssertEqual(reading.producer, "Envínate")
        XCTAssertEqual(reading.visualDescription, "a label reading }{ oddly")
    }

    func testEscapedQuotesInsideStringsAreHandled() throws {
        let text = #"{"is_wine_label": true, "visual_description": "says \"grand vin\" in gold", "producer": "Ch. Palmer"}"#
        let reading = try ModelOutputDecoder.decodeLabelReading(from: text)
        XCTAssertEqual(reading.visualDescription, #"says "grand vin" in gold"#)
    }

    /// A truncated response has to fail as a truncated response, not as a decoding oddity, so
    /// the UI can offer to retry.
    func testTruncatedJSONIsReportedAsMalformed() {
        let text = #"{"identity": {"producer": "Château Mus"#
        XCTAssertThrowsError(try ModelOutputDecoder.decodeDossier(from: text)) { error in
            guard case let .malformedJSON(underlying, _)? = error as? ResponsesError else {
                return XCTFail("Expected a malformedJSON error, got \(error)")
            }
            XCTAssertTrue(underlying.contains("No JSON object"), underlying)
        }
        XCTAssertTrue((ResponsesError.malformedJSON(underlying: "", excerpt: "")).isRetryable)
    }

    /// `DecodingError`'s own description is unreadable, and this message is what a user sees
    /// when a scan fails, so it has to name the field that was wrong.
    func testDecodingErrorsNameTheOffendingField() {
        XCTAssertThrowsError(try ModelOutputDecoder.decodeDossier(from: #"{"pairings": []}"#)) { error in
            guard case let .malformedJSON(underlying, _)? = error as? ResponsesError else {
                return XCTFail("Expected a malformedJSON error, got \(error)")
            }
            XCTAssertTrue(underlying.contains("identity"), underlying)
        }
    }

    /// One malformed section should not cost the user a correct identification.
    func testAMalformedSectionDoesNotDiscardTheWholeDossier() throws {
        let text = #"""
        {"identity":{"producer":"Tempier","wine_type":"red"},"composition":"not an array","tasting":{"structure":{"body":"very full"}}}
        """#
        let dossier = try ModelOutputDecoder.decodeDossier(from: text)
        XCTAssertEqual(dossier.identity.producer, "Tempier")
        XCTAssertTrue(dossier.composition.isEmpty)
    }

    func testMissingIdentityIsFatalBecauseThereIsNothingToShow() {
        XCTAssertThrowsError(try ModelOutputDecoder.decodeDossier(from: #"{"pairings": ["cheese"]}"#))
    }

    // MARK: - Lenient values

    func testPlaceholderStringsAreTreatedAsAbsent() throws {
        let text = #"{"is_wine_label": true, "producer": "Unknown", "cuvee": "  ", "region": "N/A", "country": "Chile"}"#
        let reading = try ModelOutputDecoder.decodeLabelReading(from: text)
        XCTAssertNil(reading.producer)
        XCTAssertNil(reading.cuvee)
        XCTAssertNil(reading.region)
        XCTAssertEqual(reading.country, "Chile")
    }

    func testConfidenceGivenAsAPercentageIsNormalised() throws {
        let reading = try ModelOutputDecoder.decodeLabelReading(from: #"{"is_wine_label": true, "confidence": 85}"#)
        XCTAssertEqual(reading.confidence.score, 0.85, accuracy: 0.001)
        XCTAssertEqual(reading.confidence.level, .high)
    }

    func testConfidenceIsClamped() {
        XCTAssertEqual(Confidence(-3).score, 0)
        XCTAssertEqual(Confidence(2).score, 1)
    }

    func testUnknownWineTypeVocabularyFallsBackRatherThanFailing() throws {
        let reading = try ModelOutputDecoder.decodeLabelReading(from: #"{"is_wine_label": true, "wine_type": "rosé"}"#)
        XCTAssertEqual(reading.wineType, .rose)

        let odd = try ModelOutputDecoder.decodeLabelReading(from: #"{"is_wine_label": true, "wine_type": "purple"}"#)
        XCTAssertEqual(odd.wineType, .other)

        let champagne = try ModelOutputDecoder.decodeLabelReading(from: #"{"is_wine_label": true, "wine_type": "Champagne"}"#)
        XCTAssertEqual(champagne.wineType, .sparkling)
    }

    func testStructureScoresAreClampedToTheScale() throws {
        let text = #"{"identity":{"producer":"X"},"tasting":{"structure":{"body":9,"acidity":0,"tannin":3}}}"#
        let dossier = try ModelOutputDecoder.decodeDossier(from: text)
        XCTAssertEqual(dossier.tasting.structure?.body, 5)
        XCTAssertEqual(dossier.tasting.structure?.acidity, 1)
        XCTAssertEqual(dossier.tasting.structure?.tannin, 3)
        XCTAssertNil(dossier.tasting.structure?.sweetness)
        XCTAssertEqual(dossier.tasting.structure?.axes.count, 3)
    }

    func testOutOfRangeSourceIndicesAreIgnoredRatherThanCrashing() {
        let attributed = Attributed(value: "Something", provenance: .web, sourceIndices: [0, 7, -1])
        let resolved = attributed.sources(in: SampleData.citations)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.url, SampleData.citations[0].url)
    }

    // MARK: - Streaming

    func testStreamedTranscriptProducesAResearchLogAndAFinalDossier() throws {
        let transcript = try Fixture.text("research_stream.sse")
        var interpreter = ResponseStreamInterpreter()

        var startedQueries: [String] = []
        var completedQueries: [String] = []
        var deltas: [String] = []
        var finalEnvelope: ResponsesEnvelope?

        for message in SSEParser.messages(in: transcript) {
            switch interpreter.interpret(message) {
            case let .searchStarted(query):
                if let query { startedQueries.append(query) }
            case let .searchCompleted(query):
                if let query { completedQueries.append(query) }
            case let .textDelta(delta):
                deltas.append(delta)
            case let .completed(envelope):
                finalEnvelope = envelope
            case let .failed(error):
                XCTFail("Unexpected failure: \(error)")
            default:
                break
            }
        }

        XCTAssertEqual(startedQueries, [
            "Domaine Tempier La Migoua 2019 tech sheet",
            "Bandol 2019 vintage report"
        ])
        // Completion events carry only an item id, so pairing them back to their query is what
        // lets the research log say which search finished.
        XCTAssertEqual(completedQueries, [
            "Domaine Tempier La Migoua 2019 tech sheet",
            "Bandol 2019 vintage report"
        ])
        XCTAssertEqual(deltas.count, 2)
        XCTAssertEqual(interpreter.text, #"{"identity":{"producer":"Domaine Tempier"}}"#)

        let envelope = try XCTUnwrap(finalEnvelope)
        XCTAssertEqual(envelope.status, "completed")
        XCTAssertEqual(envelope.annotatedURLs.count, 1)
        XCTAssertEqual(
            try ModelOutputDecoder.decodeDossier(from: envelope.outputText).identity.producer,
            "Domaine Tempier"
        )
    }

    func testParserHandlesMultiLineDataAndComments() {
        let transcript = """
        : keep-alive

        event: response.output_text.delta
        data: {"type":"response.output_text.delta",
        data: "delta":"hi"}

        """
        let messages = SSEParser.messages(in: transcript)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.event, "response.output_text.delta")

        var interpreter = ResponseStreamInterpreter()
        guard case .textDelta("hi")? = interpreter.interpret(messages[0]) else {
            return XCTFail("Expected a text delta assembled from both data lines")
        }
    }

    func testParserToleratesCRLF() {
        let transcript = "event: ping\r\ndata: {}\r\n\r\n"
        let messages = SSEParser.messages(in: transcript)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.event, "ping")
        XCTAssertEqual(messages.first?.data, "{}")
    }

    func testParserEmitsATrailingEventWithoutABlankLine() {
        var parser = SSEParser()
        XCTAssertNil(parser.consume(line: "event: response.completed"))
        XCTAssertNil(parser.consume(line: "data: {}"))
        XCTAssertEqual(parser.finish()?.event, "response.completed")
    }

    func testStreamErrorEventBecomesAFailure() {
        let transcript = """
        event: error
        data: {"type":"error","error":{"message":"Rate limit reached","code":"rate_limit_exceeded"}}

        """
        var interpreter = ResponseStreamInterpreter()
        let messages = SSEParser.messages(in: transcript)
        guard case let .failed(error)? = interpreter.interpret(messages[0]) else {
            return XCTFail("Expected a failure event")
        }
        XCTAssertEqual(error.errorDescription, "Rate limit reached")
    }

    func testTextSurvivesAStreamThatEndsWithoutCompletion() {
        let transcript = """
        event: response.output_text.delta
        data: {"delta":"{\\"identity\\":{\\"producer\\":\\"Tempier\\"}}"}

        """
        var interpreter = ResponseStreamInterpreter()
        for message in SSEParser.messages(in: transcript) {
            _ = interpreter.interpret(message)
        }
        XCTAssertEqual(interpreter.finalTextOrNil(), #"{"identity":{"producer":"Tempier"}}"#)
    }

    // MARK: - Sources

    func testAnnotatedSourcesFillInForAModelThatForgotToListThem() {
        var dossier = SampleData.dossier
        dossier.sources = []
        let merged = dossier.mergingAnnotatedSources([
            Citation(title: "Producer page", url: "https://example.com/a")
        ])
        XCTAssertEqual(merged.sources.count, 1)
    }

    func testMergingDoesNotDuplicateSourcesAlreadyListed() {
        let merged = SampleData.dossier.mergingAnnotatedSources([SampleData.citations[0]])
        XCTAssertEqual(merged.sources.count, SampleData.citations.count)
    }

    func testSourcesNoFieldPointsAtAreStillReported() {
        var dossier = SampleData.dossier
        dossier.sources.append(Citation(title: "Stray", url: "https://example.com/stray"))
        XCTAssertEqual(dossier.unreferencedSources.map(\.title), ["Stray"])
    }

    func testCitationHostDisplay() {
        XCTAssertEqual(Citation(title: "t", url: "https://www.vinous.com/x").displayHost, "vinous.com")
        XCTAssertNotNil(Citation(title: "t", url: "https://vinous.com").resolvedURL)
        XCTAssertNil(Citation(title: "t", url: "not a url").resolvedURL)
    }
}
