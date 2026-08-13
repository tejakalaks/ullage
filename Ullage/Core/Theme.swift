import SwiftUI
import UllageCore

/// Shared colours and small view helpers.
enum Theme {
    /// A deep wine red that stays legible against both light and dark backgrounds.
    static let accent = Color(red: 0.42, green: 0.09, blue: 0.16)
    static let accentLight = Color(red: 0.66, green: 0.22, blue: 0.29)

    static func color(for status: DrinkingWindow.Status) -> Color {
        switch status {
        case .tooYoung: return .blue
        case .drinkable: return .green
        case .atPeak: return accentLight
        case .fading: return .orange
        case .pastWindow: return .secondary
        case .unknown: return .secondary
        }
    }

    static func color(for provenance: Provenance) -> Color {
        switch provenance {
        case .label: return .teal
        case .web: return .blue
        case .inference: return .orange
        }
    }

    static func symbol(for provenance: Provenance) -> String {
        switch provenance {
        case .label: return "text.viewfinder"
        case .web: return "link"
        case .inference: return "sparkles"
        }
    }

    static func symbol(for wineType: WineType) -> String {
        switch wineType {
        case .sparkling: return "bubbles.and.sparkles"
        default: return "wineglass"
        }
    }
}

/// A small badge saying where a fact came from.
///
/// This is the honesty of the app made visible: a sourced claim and a guess are drawn
/// differently, and tapping either explains what that means.
struct ProvenanceBadge: View {
    let provenance: Provenance
    var sources: [Citation] = []

    @State private var isExplaining = false

    var body: some View {
        Button {
            isExplaining = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: Theme.symbol(for: provenance))
                Text(sources.first?.displayHost ?? provenance.shortLabel)
            }
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.color(for: provenance).opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.color(for: provenance))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .popover(isPresented: $isExplaining) {
            ProvenanceExplanation(provenance: provenance, sources: sources)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var accessibilityText: String {
        guard let host = sources.first?.displayHost else { return provenance.explanation }
        return "\(provenance.explanation) Source: \(host)."
    }
}

private struct ProvenanceExplanation: View {
    let provenance: Provenance
    let sources: [Citation]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(provenance.shortLabel, systemImage: Theme.symbol(for: provenance))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.color(for: provenance))

            Text(provenance.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !sources.isEmpty {
                Divider()
                ForEach(sources) { source in
                    if let url = source.resolvedURL {
                        Link(destination: url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                                .font(.footnote)
                                .lineLimit(2)
                        }
                    } else {
                        Text(source.title).font(.footnote)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: 280, alignment: .leading)
    }
}

/// A titled block used throughout the dossier.
struct DossierSection<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.accentLight)
                }
                Text(title)
                    .font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A paragraph with its provenance badge sitting under it.
struct AttributedParagraph: View {
    let title: String?
    let field: Attributed<String>
    let allSources: [Citation]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(field.value)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceBadge(provenance: field.provenance, sources: field.sources(in: allSources))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Hides a view entirely when there is nothing to show, so empty sections do not leave
    /// headings floating above blank space.
    @ViewBuilder
    func shown(if condition: Bool) -> some View {
        if condition { self }
    }
}
