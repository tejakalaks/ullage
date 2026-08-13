import SwiftUI
import UllageCore

/// The live account of what the model is doing.
///
/// A scan can take the better part of a minute, and a spinner for that long feels broken.
/// Showing the actual searches as they run turns dead time into something worth watching, and
/// it makes the app's work inspectable: you can see which sources it went to.
struct ResearchLogView: View {
    let log: ResearchLog

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(log.entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    icon(for: entry)
                        .frame(width: 20, height: 20)

                    Text(entry.text)
                        .font(.subheadline)
                        .foregroundStyle(entry.isComplete ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .animation(.easeOut(duration: 0.25), value: log)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func icon(for entry: ResearchLog.Entry) -> some View {
        if entry.isComplete {
            Image(systemName: entry.kind == .done ? "checkmark.circle.fill" : "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }
}

#Preview {
    var log = ResearchLog()
    log.apply(.readingLabel)
    log.apply(.identified(SampleData.labelReading))
    log.apply(.researching)
    log.apply(.searching(query: "Château Musar Red 2015 technical sheet"))
    log.apply(.searchFinished(query: "Château Musar Red 2015 technical sheet"))
    log.apply(.searching(query: "Bekaa Valley 2015 vintage report"))
    return ResearchLogView(log: log).padding()
}
