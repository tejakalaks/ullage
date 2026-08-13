import XCTest
@testable import UllageCore

/// The research log is the app's answer to a minute-long spinner, so its sequencing matters.
final class ResearchLogTests: XCTestCase {
    private func makeLog(_ steps: [ScanProgress]) -> ResearchLog {
        var log = ResearchLog()
        for step in steps {
            log.apply(step)
        }
        return log
    }

    func testAFullScanReadsAsACoherentStory() {
        let log = makeLog([
            .readingLabel,
            .identified(SampleData.labelReading),
            .researching,
            .searching(query: "Château Musar Red 2015 tech sheet"),
            .searchFinished(query: "Château Musar Red 2015 tech sheet"),
            .composing,
            .finished(SampleData.dossier)
        ])

        XCTAssertEqual(log.entries.map(\.text), [
            "Looking at the label",
            "Looks like Château Musar Red 2015",
            "Searching: Château Musar Red 2015 tech sheet",
            "Writing up what it found",
            "Done"
        ])
        XCTAssertTrue(log.entries.allSatisfy(\.isComplete), "Everything should be ticked off at the end")
    }

    /// The placeholder exists because the first search takes a few seconds to be announced.
    /// Once the real query arrives it must replace the placeholder rather than stack under it.
    func testTheGenericSearchLineIsReplacedByTheRealQuery() {
        let log = makeLog([.researching, .searching(query: "Bandol 2019 vintage report")])
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries.first?.text, "Searching: Bandol 2019 vintage report")
        XCTAssertEqual(log.entries.first?.kind, .search(query: "Bandol 2019 vintage report"))
    }

    func testASecondSearchGetsItsOwnLine() {
        let log = makeLog([
            .researching,
            .searching(query: "first"),
            .searching(query: "second")
        ])
        XCTAssertEqual(log.entries.map(\.text), ["Searching: first", "Searching: second"])
    }

    /// Searches overlap in practice, and completions arrive out of order. Each completion has
    /// to tick off its own line.
    func testOverlappingSearchesCompleteIndependently() {
        var log = makeLog([
            .researching,
            .searching(query: "first"),
            .searching(query: "second"),
            .searching(query: "third")
        ])
        log.apply(.searchFinished(query: "second"))

        XCTAssertEqual(log.entries.map(\.isComplete), [false, true, false])

        log.apply(.searchFinished(query: "third"))
        log.apply(.searchFinished(query: "first"))
        XCTAssertTrue(log.entries.allSatisfy(\.isComplete))
    }

    /// Some search events arrive without a query. Completing the oldest outstanding search is
    /// the best available guess and keeps the log from stalling with a spinner forever.
    func testAnUnnamedCompletionTicksOffTheOldestOutstandingSearch() {
        var log = makeLog([
            .researching,
            .searching(query: "first"),
            .searching(query: "second")
        ])
        log.apply(.searchFinished(query: nil))
        XCTAssertEqual(log.entries.map(\.isComplete), [true, false])
    }

    func testACompletionForAnUnknownQueryDoesNotTickOffTheWrongLine() {
        var log = makeLog([.researching, .searching(query: "first")])
        log.apply(.searchFinished(query: "first"))
        log.apply(.searchFinished(query: "never started"))
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertTrue(log.entries[0].isComplete)
    }

    /// A search left hanging when the model moves on would spin forever.
    func testMovingOnToWritingClosesAnyOpenSearches() {
        let log = makeLog([
            .researching,
            .searching(query: "first"),
            .searching(query: "second"),
            .composing
        ])
        let searches = log.entries.filter { $0.kind.isSearch }
        XCTAssertEqual(searches.count, 2)
        XCTAssertTrue(searches.allSatisfy(\.isComplete))
        XCTAssertEqual(log.entries.last?.kind, .writing)
        XCTAssertFalse(log.entries.last?.isComplete ?? true)
    }

    func testFinishingClosesTheWritingLineEvenWithoutAComposingEvent() {
        let log = makeLog([.researching, .searching(query: "q"), .finished(SampleData.dossier)])
        XCTAssertTrue(log.entries.allSatisfy(\.isComplete))
        XCTAssertEqual(log.entries.last?.kind, .done)
    }

    func testCurrentActivityIsTheNewestUnfinishedLine() {
        var log = makeLog([.readingLabel])
        XCTAssertEqual(log.currentActivity, "Looking at the label")

        log.apply(.identified(SampleData.labelReading))
        // Nothing is in flight between the two passes, so the last thing that happened is the
        // honest thing to show.
        XCTAssertEqual(log.currentActivity, "Looks like Château Musar Red 2015")

        log.apply(.researching)
        XCTAssertEqual(log.currentActivity, "Searching the web")
    }

    func testResearchOnlyRunsSkipTheIdentificationLines() {
        let log = makeLog([.researching, .searching(query: "Ridge Monte Bello 2016"), .composing])
        XCTAssertFalse(log.entries.contains { $0.kind == .reading || $0.kind == .identified })
    }

    func testAnEmptyLogHasNoActivity() {
        XCTAssertNil(ResearchLog().currentActivity)
        XCTAssertTrue(ResearchLog().isEmpty)
    }

    func testResetClearsEverything() {
        var log = makeLog([.readingLabel, .researching])
        log.removeAll()
        XCTAssertTrue(log.isEmpty)
    }
}
