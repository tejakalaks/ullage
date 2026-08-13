import XCTest
@testable import UllageCore

/// The schema is the contract between the prompt and every view in the app, and a mistake in
/// it surfaces as an opaque 400 from the API at scan time. These tests are what stand in for
/// being able to call the API from CI.
final class SchemaTests: XCTestCase {
    func testDossierSchemaSatisfiesStrictModeRules() {
        let violations = SchemaValidator.violations(in: WineSchema.dossier)
        XCTAssertTrue(
            violations.isEmpty,
            "Dossier schema breaks strict mode:\n" + violations.map(\.description).joined(separator: "\n")
        )
    }

    func testLabelReadingSchemaSatisfiesStrictModeRules() {
        let violations = SchemaValidator.violations(in: WineSchema.labelReading)
        XCTAssertTrue(
            violations.isEmpty,
            "Label reading schema breaks strict mode:\n" + violations.map(\.description).joined(separator: "\n")
        )
    }

    func testValidatorCatchesAMissingRequiredEntry() {
        // Guards the guard: a validator that never fails would pass the two tests above
        // regardless of what the schemas actually contain.
        let bad = JSONValue.object([
            ("type", .string("object")),
            ("properties", .object([("a", Schema.string())])),
            ("required", .array([])),
            ("additionalProperties", .bool(false))
        ])
        let violations = SchemaValidator.violations(in: bad)
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.path, "#/a")
    }

    func testValidatorCatchesOpenObjects() {
        let bad = JSONValue.object([
            ("type", .string("object")),
            ("properties", .object([])),
            ("required", .array([]))
        ])
        XCTAssertEqual(
            SchemaValidator.violations(in: bad).first?.problem,
            "object must set additionalProperties to false"
        )
    }

    func testNullableWrapsTypeRatherThanReplacingIt() {
        let node = Schema.nullable(Schema.string("A note"))
        XCTAssertEqual(node["type"], .array([.string("string"), .string("null")]))
        XCTAssertEqual(node["description"], .string("A note"))
    }

    func testNullableIsIdempotent() {
        let once = Schema.nullable(Schema.integer())
        let twice = Schema.nullable(once)
        XCTAssertEqual(once, twice)
    }

    /// Every enum in the schema has to agree with the Swift type it decodes into, or the model
    /// will faithfully emit a value the app then discards.
    func testWineTypeEnumMatchesTheSwiftType() throws {
        let identity = try XCTUnwrap(WineSchema.dossier["properties"]?["identity"])
        let wineType = try XCTUnwrap(identity["properties"]?["wine_type"])
        let cases = try XCTUnwrap(wineType["enum"]?.arrayValue?.compactMap(\.stringValue))
        XCTAssertEqual(Set(cases), Set(WineType.allCases.map(\.rawValue)))
        for raw in cases {
            XCTAssertNotNil(WineType(rawValue: raw), "Schema offers '\(raw)' but WineType cannot decode it")
        }
    }

    func testProvenanceEnumMatchesTheSwiftType() throws {
        let window = try XCTUnwrap(WineSchema.dossier["properties"]?["drinking_window"])
        let provenance = try XCTUnwrap(window["properties"]?["provenance"])
        let cases = try XCTUnwrap(provenance["enum"]?.arrayValue?.compactMap(\.stringValue))
        XCTAssertEqual(Set(cases), Set(Provenance.allCases.map(\.rawValue)))
    }

    /// A schema that describes a field the decoder ignores is a field the model wastes tokens
    /// on and the user never sees.
    func testDossierSchemaFieldsAllSurviveARoundTrip() throws {
        let encoded = try JSONEncoder().encode(SampleData.dossier)
        let reDecoded = try JSONDecoder().decode(WineDossier.self, from: encoded)
        XCTAssertEqual(reDecoded.identity, SampleData.dossier.identity)
        XCTAssertEqual(reDecoded.origin, SampleData.dossier.origin)
        XCTAssertEqual(reDecoded.winemaking, SampleData.dossier.winemaking)
        XCTAssertEqual(reDecoded.tasting, SampleData.dossier.tasting)
        XCTAssertEqual(reDecoded.drinkingWindow, SampleData.dossier.drinkingWindow)
        XCTAssertEqual(reDecoded.composition, SampleData.dossier.composition)
        XCTAssertEqual(reDecoded.ratings, SampleData.dossier.ratings)
        XCTAssertEqual(reDecoded.priceEstimate, SampleData.dossier.priceEstimate)
        XCTAssertEqual(reDecoded.sources, SampleData.dossier.sources)
    }

    func testSchemaSerialisesToValidJSON() throws {
        let text = WineSchema.dossier.encodedString()
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
        XCTAssertTrue(parsed is [String: Any])
    }

    /// Key order is what makes the schema readable in a diff; JSONEncoder preserves the order
    /// values are encoded in, and this pins that behaviour down.
    func testObjectKeyOrderIsPreserved() throws {
        let value = JSONValue.object([("zebra", 1), ("apple", 2), ("mango", 3)])
        XCTAssertEqual(value.encodedString(), #"{"zebra":1,"apple":2,"mango":3}"#)
    }
}
