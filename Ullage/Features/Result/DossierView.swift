import SwiftUI
import UllageCore
import UIKit

/// The finished profile of a bottle.
struct DossierView: View {
    let dossier: WineDossier
    var labelImage: UIImage?
    var onSave: (() -> Void)?
    var isSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if let summary = dossier.identity.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                DrinkingWindowView(window: dossier.drinkingWindow, allSources: dossier.sources)
                    .shown(if: !dossier.drinkingWindow.isEmpty)

                originSection
                compositionSection
                winemakingSection
                tastingSection
                pairingsSection

                // Grouped only because ViewBuilder takes at most ten children.
                Group {
                    ratingsSection
                    priceSection
                    confidenceSection
                    sourcesSection
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if let onSave {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSave) {
                        Label(
                            isSaved ? "Saved to cellar" : "Save to cellar",
                            systemImage: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down"
                        )
                    }
                    .disabled(isSaved)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let labelImage {
                    Image(uiImage: labelImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 76, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(dossier.identity.displayTitle)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = dossier.displaySubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Label(dossier.identity.vintageText, systemImage: "calendar")
                        if let abv = dossier.identity.alcoholPercent {
                            Label(String(format: "%.1f%%", abv), systemImage: "drop")
                        }
                        if let size = dossier.identity.bottleSizeMilliliters {
                            Label("\(size)ml", systemImage: Theme.symbol(for: dossier.identity.wineType))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }

            if !dossier.winemaking.certifications.isEmpty {
                HStack(spacing: 6) {
                    ForEach(dossier.winemaking.certifications, id: \.self) { certification in
                        Text(certification)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sections

    @ViewBuilder
    private var originSection: some View {
        let hierarchy = dossier.origin.hierarchy
        if !hierarchy.isEmpty || dossier.origin.terroirNotes != nil {
            DossierSection(title: "Where it comes from", systemImage: "map") {
                // Broad to narrow, so the place reads the way a wine label describes it.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(hierarchy.enumerated()), id: \.offset) { index, level in
                        HStack(spacing: 8) {
                            Image(systemName: index == hierarchy.count - 1 ? "mappin.circle.fill" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(index == hierarchy.count - 1 ? Theme.accentLight : .secondary)
                                .frame(width: 16)
                            Text(level.value)
                                .font(index == hierarchy.count - 1 ? .body.weight(.medium) : .body)
                            ProvenanceBadge(
                                provenance: level.provenance,
                                sources: level.sources(in: dossier.sources)
                            )
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, CGFloat(index) * 10)
                    }
                }

                if let classification = dossier.origin.classification {
                    Divider()
                    AttributedParagraph(
                        title: "Classification",
                        field: classification,
                        allSources: dossier.sources
                    )
                }

                if let terroir = dossier.origin.terroirNotes {
                    Divider()
                    AttributedParagraph(title: "Terroir", field: terroir, allSources: dossier.sources)
                }
            }
        }
    }

    @ViewBuilder
    private var compositionSection: some View {
        if !dossier.composition.isEmpty {
            DossierSection(title: "Grapes", systemImage: "leaf") {
                ForEach(dossier.composition) { grape in
                    HStack {
                        Text(grape.name)
                        Spacer()
                        if let percentage = grape.percentageText {
                            Text(percentage)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let percentage = grape.percentage {
                        ProgressView(value: min(max(percentage / 100, 0), 1))
                            .tint(Theme.accentLight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var winemakingSection: some View {
        if !dossier.winemaking.isEmpty {
            DossierSection(title: "In the winery", systemImage: "hammer") {
                if let notes = dossier.winemaking.winemakerNotes {
                    // The producer's own words are the point of the app, so they are set apart
                    // rather than filed under a subheading with everything else.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("From the winemaker")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accentLight)
                        Text(notes.value)
                            .font(.body)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(Theme.accentLight.opacity(0.4))
                                    .frame(width: 3)
                            }
                        ProvenanceBadge(
                            provenance: notes.provenance,
                            sources: notes.sources(in: dossier.sources)
                        )
                    }
                    if dossier.winemaking.vinification != nil || dossier.winemaking.aging != nil
                        || dossier.winemaking.viticulture != nil {
                        Divider()
                    }
                }

                if let vinification = dossier.winemaking.vinification {
                    AttributedParagraph(title: "Vinification", field: vinification, allSources: dossier.sources)
                }
                if let aging = dossier.winemaking.aging {
                    AttributedParagraph(title: "Ageing", field: aging, allSources: dossier.sources)
                }
                if let viticulture = dossier.winemaking.viticulture {
                    AttributedParagraph(title: "In the vineyard", field: viticulture, allSources: dossier.sources)
                }
                if let production = dossier.winemaking.productionQuantity {
                    AttributedParagraph(title: "Production", field: production, allSources: dossier.sources)
                }
            }
        }
    }

    @ViewBuilder
    private var tastingSection: some View {
        if !dossier.tasting.isEmpty {
            DossierSection(title: "How it tastes", systemImage: "nose") {
                if let nose = dossier.tasting.nose {
                    AttributedParagraph(title: "Nose", field: nose, allSources: dossier.sources)
                }
                if let palate = dossier.tasting.palate {
                    AttributedParagraph(title: "Palate", field: palate, allSources: dossier.sources)
                }
                if let finish = dossier.tasting.finish {
                    AttributedParagraph(title: "Finish", field: finish, allSources: dossier.sources)
                }
                if let structure = dossier.tasting.structure, !structure.axes.isEmpty {
                    Divider()
                    StructureChart(structure: structure)
                }
            }
        }
    }

    @ViewBuilder
    private var pairingsSection: some View {
        if !dossier.pairings.isEmpty {
            DossierSection(title: "Serve it with", systemImage: "fork.knife") {
                ForEach(dossier.pairings, id: \.self) { pairing in
                    Label(pairing, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var ratingsSection: some View {
        if !dossier.ratings.isEmpty {
            DossierSection(title: "What critics said", systemImage: "star") {
                ForEach(dossier.ratings) { rating in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(rating.critic)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(rating.displayScore)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.accentLight)
                        }
                        if let excerpt = rating.reviewExcerpt {
                            Text("“\(excerpt)”")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let index = rating.sourceIndex, dossier.sources.indices.contains(index),
                           let url = dossier.sources[index].resolvedURL {
                            Link(dossier.sources[index].displayHost, destination: url)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var priceSection: some View {
        if let price = dossier.priceEstimate, !price.isEmpty, let range = price.displayRange {
            DossierSection(title: "Roughly what it costs", systemImage: "tag") {
                HStack(alignment: .firstTextBaseline) {
                    Text(range)
                        .font(.title3.weight(.semibold))
                    if let market = price.market {
                        Text(market)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                ProvenanceBadge(
                    provenance: price.provenance,
                    sources: price.sourceIndices.compactMap {
                        dossier.sources.indices.contains($0) ? dossier.sources[$0] : nil
                    }
                )
            }
        }
    }

    private var confidenceSection: some View {
        DossierSection(title: "How sure is this?", systemImage: "checkmark.shield") {
            HStack {
                Text(dossier.overallConfidence.level.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(dossier.overallConfidence.percentText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: dossier.overallConfidence.score)
                .tint(dossier.overallConfidence.level == .low ? .orange : Theme.accentLight)

            if let notes = dossier.researchNotes {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Researched \(dossier.generatedAt.formatted(date: .abbreviated, time: .shortened)).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        if !dossier.sources.isEmpty {
            DossierSection(title: "Sources", systemImage: "link") {
                ForEach(dossier.sources) { source in
                    if let url = source.resolvedURL {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 4) {
                                    Text(source.displayHost)
                                    if let note = source.note {
                                        Text("· \(note)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(source.title).font(.subheadline)
                    }
                }
            }
        }
    }
}

/// The 1–5 structural axes as bars.
struct StructureChart: View {
    let structure: WineDossier.Tasting.Structure

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(structure.axes) { axis in
                HStack(spacing: 10) {
                    Text(axis.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .leading)
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { step in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(step <= axis.value ? Theme.accentLight : Color(.quaternaryLabel))
                                .frame(height: 8)
                        }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(axis.name) \(axis.value) out of 5")
            }
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(Theme.accentLight)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        DossierView(dossier: SampleData.dossier, onSave: {})
            .navigationTitle("Musar 2015")
            .navigationBarTitleDisplayMode(.inline)
    }
}
