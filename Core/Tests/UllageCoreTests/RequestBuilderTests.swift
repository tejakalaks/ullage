import XCTest
@testable import UllageCore

/// What actually goes over the wire. The distinction between the two passes — one looking at
/// the bottle with no tools, one researching with search on — is the core of the design, so
/// it is asserted rather than assumed.
final class RequestBuilderTests: XCTestCase {
    private let options = ResponsesRequest.Options(
        model: "gpt-5-mini",
        enableWebSearch: true,
        reasoningEffort: "low"
    )

    private let image = ResponsesRequest.ImagePayload(
        dataURL: "data:image/jpeg;base64,AAAA",
        role: "front label"
    )

    func testLabelReadingPassDoesNotSearchTheWeb() {
        let body = ResponsesRequest.labelReading(images: [image], options: options, stream: false)
        XCTAssertNil(body["tools"], "Stage A must look at the photograph, not the web")
        XCTAssertEqual(body["model"], .string("gpt-5-mini"))
        XCTAssertEqual(body["stream"], .bool(false))
    }

    func testResearchPassEnablesWebSearch() {
        let body = ResponsesRequest.research(prompt: "Research this", images: [], options: options, stream: true)
        XCTAssertEqual(body["tools"], .array([.object([("type", .string("web_search"))])]))
        XCTAssertEqual(body["stream"], .bool(true))
    }

    func testWebSearchCanBeTurnedOff() {
        let offline = ResponsesRequest.Options(model: "gpt-5-mini", enableWebSearch: false)
        let body = ResponsesRequest.research(prompt: "Research this", images: [], options: offline, stream: false)
        XCTAssertNil(body["tools"])
    }

    func testBothPassesRequestStrictStructuredOutput() throws {
        for body in [
            ResponsesRequest.labelReading(images: [image], options: options, stream: false),
            ResponsesRequest.research(prompt: "x", images: [], options: options, stream: false)
        ] {
            let format = try XCTUnwrap(body["text"]?["format"])
            XCTAssertEqual(format["type"], .string("json_schema"))
            XCTAssertEqual(format["strict"], .bool(true))
            XCTAssertNotNil(format["schema"])
        }
    }

    func testLabelPhotographsAreSentAtHighDetail() throws {
        let body = ResponsesRequest.labelReading(images: [image], options: options, stream: false)
        let content = try XCTUnwrap(body["input"]?.arrayValue?.first?["content"]?.arrayValue)
        let imagePart = try XCTUnwrap(content.first { $0["type"] == .string("input_image") })
        XCTAssertEqual(imagePart["detail"], .string("high"))
        XCTAssertEqual(imagePart["image_url"], .string("data:image/jpeg;base64,AAAA"))
    }

    /// Telling the model which photo is the back label is what gets the small print read.
    func testImageRoleIsAnnouncedBeforeTheImage() throws {
        let body = ResponsesRequest.labelReading(
            images: [ResponsesRequest.ImagePayload(dataURL: "data:image/jpeg;base64,BBBB", role: "back label")],
            options: options,
            stream: false
        )
        let content = try XCTUnwrap(body["input"]?.arrayValue?.first?["content"]?.arrayValue)
        XCTAssertEqual(content.first?["text"], .string("This photograph is the back label."))
    }

    func testMultipleImagesAddTheBackLabelGuidance() throws {
        let single = ResponsesRequest.labelReading(images: [image], options: options, stream: false)
        let pair = ResponsesRequest.labelReading(images: [image, image], options: options, stream: false)
        let singleInstructions = try XCTUnwrap(single["instructions"]?.stringValue)
        let pairInstructions = try XCTUnwrap(pair["instructions"]?.stringValue)
        XCTAssertFalse(singleInstructions.contains("back label usually carries"))
        XCTAssertTrue(pairInstructions.contains("back label usually carries"))
    }

    /// The research pass gets the photographs back at low detail so it can double-check the
    /// bottle without paying full price for the pixels a second time.
    func testResearchPassRevisitsThePhotographsCheaply() throws {
        let body = ResponsesRequest.research(prompt: "Research", images: [image], options: options, stream: false)
        let content = try XCTUnwrap(body["input"]?.arrayValue?.first?["content"]?.arrayValue)
        let imagePart = try XCTUnwrap(content.first { $0["type"] == .string("input_image") })
        XCTAssertEqual(imagePart["detail"], .string("low"))
    }

    func testResponsesAreNotStoredServerSide() {
        let body = ResponsesRequest.research(prompt: "x", images: [], options: options, stream: false)
        XCTAssertEqual(body["store"], .bool(false), "Label photographs belong to the user")
    }

    func testReasoningEffortIsOmittedWhenNotSet() {
        let plain = ResponsesRequest.Options(model: "gpt-4.1", enableWebSearch: true)
        let body = ResponsesRequest.research(prompt: "x", images: [], options: plain, stream: false)
        XCTAssertNil(body["reasoning"])
    }

    func testRequestBodySerialisesToValidJSON() throws {
        let body = ResponsesRequest.research(prompt: "Research this", images: [image], options: options, stream: true)
        let text = body.encodedString()
        XCTAssertTrue(try JSONSerialization.jsonObject(with: Data(text.utf8)) is [String: Any])
        // Slashes in data URLs must not come back escaped, or the API rejects the image.
        XCTAssertTrue(text.contains("data:image/jpeg;base64,AAAA"))
    }

    // MARK: - Prompt assembly

    func testResearchPromptCarriesTheLabelReadingForward() {
        let prompt = StagePrompts.researchRequest(for: SampleData.labelReading, currentYear: 2026)
        XCTAssertTrue(prompt.contains("Château Musar"))
        XCTAssertTrue(prompt.contains("Vintage: 2015"))
        XCTAssertTrue(prompt.contains("Bekaa Valley"))
        XCTAssertTrue(prompt.contains("The current year is 2026"))
        XCTAssertTrue(prompt.contains("Château Musar Red 2015 technical sheet"))
    }

    func testAnUncertainReadingAsksTheResearchPassToVerifyIt() {
        var unsure = SampleData.labelReading
        unsure.confidence = Confidence(0.35)
        unsure.alternatives = [
            LabelReading.Alternative(description: "Musar Jeune 2015", confidence: Confidence(0.3))
        ]
        let prompt = StagePrompts.researchRequest(for: unsure, currentYear: 2026)
        XCTAssertTrue(prompt.contains("Verify it against what you find online"))
        XCTAssertTrue(prompt.contains("Musar Jeune 2015"))
    }

    func testAConfidentReadingDoesNotAskForVerification() {
        let prompt = StagePrompts.researchRequest(for: SampleData.labelReading, currentYear: 2026)
        XCTAssertFalse(prompt.contains("Verify it against"))
    }

    func testManualEntryIsTreatedAsAuthoritative() {
        let prompt = StagePrompts.researchRequest(forManualEntry: "Ridge Monte Bello 2016", currentYear: 2026)
        XCTAssertTrue(prompt.contains("Ridge Monte Bello 2016"))
        XCTAssertTrue(prompt.contains("authoritative"))
    }

    func testNonVintageBottlesAreDescribedAsSuch() {
        var champagne = LabelReading(producer: "Jacques Selosse", isNonVintage: true)
        champagne.appellation = "Champagne"
        XCTAssertEqual(champagne.displayTitle, "Jacques Selosse NV")
        XCTAssertTrue(StagePrompts.labelSummary(for: champagne).contains("Vintage: non-vintage"))
    }

    func testResearchSubjectCollapsesRepeatedPlaceNames() {
        let reading = LabelReading(
            producer: "Bodega X",
            appellation: "Rioja",
            region: "Rioja",
            country: "Spain"
        )
        XCTAssertEqual(reading.researchSubject, "Bodega X, Rioja, Spain")
    }

    func testALabelWithNothingIdentifiableIsFlagged() {
        let reading = LabelReading(producer: nil, cuvee: nil, appellation: nil)
        XCTAssertFalse(reading.isIdentifiable)
        XCTAssertEqual(reading.displayTitle, "Unidentified wine")
    }

    func testANonWineLabelIsNeverIdentifiable() {
        let reading = LabelReading(isWineLabel: false, producer: "Filippo Berio")
        XCTAssertFalse(reading.isIdentifiable)
    }
}
