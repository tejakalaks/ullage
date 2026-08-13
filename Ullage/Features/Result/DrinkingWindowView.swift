import SwiftUI
import UllageCore

/// The drinking window, drawn as a timeline with the peak marked and "now" on it.
///
/// This is the question most people actually have when they pick up a bottle, so it gets a
/// picture rather than a line of text.
struct DrinkingWindowView: View {
    let window: DrinkingWindow
    let allSources: [Citation]
    var year: Int = Calendar.current.component(.year, from: Date())

    private var status: DrinkingWindow.Status { window.status(asOf: year) }

    var body: some View {
        DossierSection(title: "Drinking window", systemImage: "calendar") {
            HStack(alignment: .firstTextBaseline) {
                Text(status.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.color(for: status))
                Spacer()
                if let range = window.yearRangeDescription {
                    Text(range)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if window.startYear != nil || window.endYear != nil {
                timeline
            }

            if let peak = window.peakRangeDescription {
                Label("Peak \(peak)", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accentLight)
            }

            if let advice = window.advice {
                Text(advice)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            servingDetails

            ProvenanceBadge(
                provenance: window.provenance,
                sources: window.sourceIndices.compactMap {
                    allSources.indices.contains($0) ? allSources[$0] : nil
                }
            )
        }
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 8)

                if let peakFraction = peakFraction {
                    Capsule()
                        .fill(Theme.accentLight.opacity(0.35))
                        .frame(width: max(width * peakFraction.width, 4), height: 8)
                        .offset(x: width * peakFraction.start)
                }

                if let progress = window.progress(asOf: year) {
                    Circle()
                        .fill(Theme.color(for: status))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        // Inset by the marker's own width so it stays inside the track at
                        // either end rather than hanging off it.
                        .offset(x: (width - 14) * progress)
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    /// Where the peak sits along the overall window, as fractions of its width.
    private var peakFraction: (start: Double, width: Double)? {
        guard let start = window.startYear,
              let end = window.endYear,
              end > start,
              let peakStart = window.peakStartYear,
              let peakEnd = window.peakEndYear
        else { return nil }
        let span = Double(end - start)
        let clampedStart = min(max(Double(peakStart - start) / span, 0), 1)
        let clampedEnd = min(max(Double(peakEnd - start) / span, 0), 1)
        return (clampedStart, max(clampedEnd - clampedStart, 0.02))
    }

    private struct ServingItem: Identifiable {
        var label: String
        var value: String

        var id: String { label }
    }

    @ViewBuilder
    private var servingDetails: some View {
        let details = servingItems
        if !details.isEmpty {
            HStack(spacing: 18) {
                ForEach(details) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }

    private var servingItems: [ServingItem] {
        var items: [ServingItem] = []
        if let minutes = window.decantMinutes, minutes > 0 {
            let value = minutes >= 60
                ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")"
                : "\(minutes) min"
            items.append(ServingItem(label: "Decant", value: value))
        }
        if let temperature = window.servingTemperatureCelsius {
            items.append(ServingItem(label: "Serve at", value: temperature.formatted()))
        }
        return items
    }

    private var accessibilityDescription: String {
        var parts = [status.headline]
        if let range = window.yearRangeDescription {
            parts.append("window \(range)")
        }
        if let peak = window.peakRangeDescription {
            parts.append("peak \(peak)")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            DrinkingWindowView(
                window: SampleData.dossier.drinkingWindow,
                allSources: SampleData.citations,
                year: 2026
            )
            DrinkingWindowView(
                window: DrinkingWindow(startYear: 2032, endYear: 2050, advice: "Far too young."),
                allSources: [],
                year: 2026
            )
            DrinkingWindowView(
                window: DrinkingWindow(startYear: 2005, endYear: 2015),
                allSources: [],
                year: 2026
            )
        }
        .padding()
    }
}
