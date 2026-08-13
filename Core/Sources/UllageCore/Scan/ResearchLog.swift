import Foundation

/// The running account of what the model is doing during a scan.
///
/// Kept here rather than in the view so the sequencing can be tested. The fiddly parts are
/// pairing a search's completion back to the query that started it, and not leaving a vague
/// "Searching the web" line sitting above the specific query that replaced it.
public struct ResearchLog: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reading
        case identified
        case search(query: String?)
        case writing
        case done

        var isSearch: Bool {
            if case .search = self { return true }
            return false
        }
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var kind: Kind
        public var text: String
        public var isComplete: Bool

        public init(id: UUID = UUID(), kind: Kind, text: String, isComplete: Bool) {
            self.id = id
            self.kind = kind
            self.text = text
            self.isComplete = isComplete
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// The line to show as the current activity: the newest thing still in progress, or the
    /// last thing that happened if everything is done.
    public var currentActivity: String? {
        entries.last(where: { !$0.isComplete })?.text ?? entries.last?.text
    }

    public var isEmpty: Bool { entries.isEmpty }

    public mutating func removeAll() {
        entries.removeAll()
    }

    public mutating func apply(_ progress: ScanProgress) {
        switch progress {
        case .readingLabel:
            entries.append(Entry(kind: .reading, text: "Looking at the label", isComplete: false))

        case let .identified(reading):
            complete(where: { $0 == .reading })
            entries.append(Entry(
                kind: .identified,
                text: "Looks like \(reading.displayTitle)",
                isComplete: true
            ))

        case .researching:
            // A placeholder, because the first search often takes a few seconds to be
            // announced and silence in the meantime reads as a stall.
            entries.append(Entry(kind: .search(query: nil), text: "Searching the web", isComplete: false))

        case let .searching(query):
            adoptOrAppendSearch(query: query)

        case let .searchFinished(query):
            completeSearch(query: query)

        case .composing:
            complete(where: { $0.isSearch })
            entries.append(Entry(kind: .writing, text: "Writing up what it found", isComplete: false))

        case .finished:
            complete(where: { $0.isSearch || $0 == .writing })
            entries.append(Entry(kind: .done, text: "Done", isComplete: true))
        }
    }

    /// Fills in the unnamed placeholder if one is waiting, rather than stacking a vague line
    /// above the specific query that supersedes it.
    private mutating func adoptOrAppendSearch(query: String?) {
        let text = query.map { "Searching: \($0)" } ?? "Searching the web"
        if let index = entries.lastIndex(where: { $0.kind == .search(query: nil) && !$0.isComplete }) {
            entries[index].kind = .search(query: query)
            entries[index].text = text
        } else {
            entries.append(Entry(kind: .search(query: query), text: text, isComplete: false))
        }
    }

    /// Completion events carry only an item id, which the stream interpreter has already
    /// resolved back to a query. Matching on that query means finishing the right line when
    /// several searches are in flight at once, which they routinely are.
    private mutating func completeSearch(query: String?) {
        if let query,
           let index = entries.lastIndex(where: { $0.kind == .search(query: query) && !$0.isComplete }) {
            entries[index].isComplete = true
            return
        }
        if let index = entries.firstIndex(where: { $0.kind.isSearch && !$0.isComplete }) {
            entries[index].isComplete = true
        }
    }

    private mutating func complete(where predicate: (Kind) -> Bool) {
        for index in entries.indices where predicate(entries[index].kind) {
            entries[index].isComplete = true
        }
    }
}
