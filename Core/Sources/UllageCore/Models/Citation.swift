import Foundation

/// A web source the research pass leaned on.
public struct Citation: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var url: String
    /// What this source contributed, e.g. "producer tech sheet" or "vintage report".
    public var note: String?

    public var id: String { url.isEmpty ? title : url }

    public init(title: String, url: String, note: String? = nil) {
        self.title = title
        self.url = url
        self.note = note
    }

    /// Host name for compact display, e.g. "vinous.com".
    public var displayHost: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var resolvedURL: URL? {
        guard let url = URL(string: url), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}
