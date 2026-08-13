import XCTest
@testable import UllageCore

/// The drinking window is the one thing in the app that changes meaning with time, so its
/// status is computed rather than stored. These tests pin down the boundaries.
final class DrinkingWindowTests: XCTestCase {
    private let window = DrinkingWindow(
        startYear: 2024,
        endYear: 2038,
        peakStartYear: 2028,
        peakEndYear: 2034
    )

    func testStatusBeforeTheWindowOpens() {
        XCTAssertEqual(window.status(asOf: 2023), .tooYoung)
    }

    func testStatusOnTheOpeningYear() {
        XCTAssertEqual(window.status(asOf: 2024), .drinkable)
    }

    func testStatusInsideTheWindowButBeforePeak() {
        XCTAssertEqual(window.status(asOf: 2026), .drinkable)
    }

    func testStatusAtPeakIncludesBothPeakBoundaries() {
        XCTAssertEqual(window.status(asOf: 2028), .atPeak)
        XCTAssertEqual(window.status(asOf: 2031), .atPeak)
        XCTAssertEqual(window.status(asOf: 2034), .atPeak)
    }

    func testStatusAfterPeakButInsideWindow() {
        XCTAssertEqual(window.status(asOf: 2035), .drinkable)
    }

    /// The final year of the window is called out separately: "drink up" and "no rush" are
    /// different advice, and a bottle in its last year deserves the former.
    func testFinalYearOfTheWindowSaysDrinkUp() {
        XCTAssertEqual(window.status(asOf: 2038), .fading)
    }

    func testStatusAfterTheWindowCloses() {
        XCTAssertEqual(window.status(asOf: 2039), .pastWindow)
    }

    func testStatusIsUnknownWithoutAnyYears() {
        XCTAssertEqual(DrinkingWindow().status(asOf: 2030), .unknown)
    }

    func testOpenEndedWindowFromAStartYear() {
        let openEnded = DrinkingWindow(startYear: 2030)
        XCTAssertEqual(openEnded.status(asOf: 2029), .tooYoung)
        XCTAssertEqual(openEnded.status(asOf: 2031), .drinkable)
        XCTAssertNil(openEnded.progress(asOf: 2031), "An open-ended window cannot honestly show progress")
    }

    /// A peak that sits outside the stated window is contradictory, and the peak is the more
    /// specific claim, so it wins.
    func testPeakOutsideTheWindowStillReportsPeak() {
        let contradictory = DrinkingWindow(
            startYear: 2024,
            endYear: 2030,
            peakStartYear: 2032,
            peakEndYear: 2034
        )
        XCTAssertEqual(contradictory.status(asOf: 2033), .atPeak)
    }

    func testProgressAcrossTheWindow() throws {
        XCTAssertEqual(try XCTUnwrap(window.progress(asOf: 2024)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(window.progress(asOf: 2031)), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(window.progress(asOf: 2038)), 1, accuracy: 0.001)
    }

    func testProgressClampsOutsideTheWindow() throws {
        XCTAssertEqual(try XCTUnwrap(window.progress(asOf: 2010)), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(window.progress(asOf: 2099)), 1, accuracy: 0.001)
    }

    func testSingleYearWindowDoesNotDivideByZero() {
        let single = DrinkingWindow(startYear: 2030, endYear: 2030)
        XCTAssertNil(single.progress(asOf: 2030))
        XCTAssertEqual(single.status(asOf: 2030), .fading)
    }

    func testYearRangeDescriptions() {
        XCTAssertEqual(window.yearRangeDescription, "2024 – 2038")
        XCTAssertEqual(DrinkingWindow(startYear: 2027).yearRangeDescription, "from 2027")
        XCTAssertEqual(DrinkingWindow(endYear: 2029).yearRangeDescription, "through 2029")
        XCTAssertNil(DrinkingWindow().yearRangeDescription)
    }

    func testTemperatureRangeNormalisesInvertedBounds() {
        let range = ClosedRangeBox(lower: 18, upper: 16)
        XCTAssertEqual(range.lower, 16)
        XCTAssertEqual(range.upper, 18)
        XCTAssertEqual(range.formatted(), "16–18°C")
    }

    func testServingTemperatureFallsBackToTheConventionForTheStyle() {
        var dossier = SampleData.dossier
        dossier.drinkingWindow.servingTemperatureCelsius = nil
        let (range, isConventional) = dossier.servingTemperature
        XCTAssertTrue(isConventional)
        XCTAssertEqual(range, WineType.red.conventionalServingTemperature)
    }

    func testStatedServingTemperatureWinsOverTheConvention() {
        let (range, isConventional) = SampleData.dossier.servingTemperature
        XCTAssertFalse(isConventional)
        XCTAssertEqual(range, ClosedRangeBox(lower: 16, upper: 18))
    }
}
