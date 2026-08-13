import Foundation

/// What a scan reports as it happens.
///
/// A scan takes long enough — a vision pass plus several web searches — that narrating it is
/// not a nicety. Each case corresponds to something the interface can say out loud.
public enum ScanProgress: Sendable {
    /// The vision pass is looking at the photographs.
    case readingLabel
    /// The vision pass finished; the first moment there is anything to show.
    case identified(LabelReading)
    /// The research pass began.
    case researching
    /// The model started a web search. Nil when the API reports a search without its query.
    case searching(query: String?)
    case searchFinished(query: String?)
    /// The dossier JSON is arriving.
    case composing
    case finished(WineDossier)
}
