import SwiftData
import SwiftUI
import UllageCore
import UIKit

/// Every bottle scanned and kept.
struct CellarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanRecord.savedAt, order: .reverse) private var records: [ScanRecord]
    @State private var searchText = ""

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("Nothing in the cellar", systemImage: "square.stack.3d.up.slash")
                } description: {
                    Text("Scan a bottle and save it, and it will be here.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Cellar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        List {
            ForEach(filtered) { record in
                NavigationLink {
                    detail(for: record)
                } label: {
                    row(record)
                }
            }
            .onDelete(perform: delete)
        }
        .searchable(text: $searchText, prompt: "Producer, wine or region")
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private var filtered: [ScanRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            [record.producer, record.wineName, record.regionSummary, record.vintageText]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func row(_ record: ScanRecord) -> some View {
        HStack(spacing: 12) {
            thumbnail(record)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(record.vintageText)
                    if let region = record.regionSummary {
                        Text("· \(region)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Recomputed on every render, so a bottle saved years ago reports where it is
                // in its life now rather than when it was scanned.
                let status = record.drinkingStatus
                if status != .unknown {
                    Text(status.headline)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.color(for: status).opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.color(for: status))
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func thumbnail(_ record: ScanRecord) -> some View {
        if let data = record.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 44, height: 58)
                .overlay {
                    Image(systemName: "wineglass")
                        .foregroundStyle(Theme.accentLight)
                }
        }
    }

    @ViewBuilder
    private func detail(for record: ScanRecord) -> some View {
        if let dossier = record.dossier {
            DossierView(
                dossier: dossier,
                labelImage: record.thumbnailData.flatMap(UIImage.init(data:))
            )
            .navigationTitle(record.vintageText)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                "This one can't be opened",
                systemImage: "exclamationmark.triangle",
                description: Text("It was saved by a different version of Ullage.")
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { filtered[$0] }
        for record in toDelete {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        CellarView()
    }
    .modelContainer(for: ScanRecord.self, inMemory: true)
}
