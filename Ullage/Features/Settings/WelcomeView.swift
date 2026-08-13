import SwiftUI

/// Shown once, on first launch.
///
/// It exists to make one decision easy: add a key now, or look around on sample data first.
/// Demanding an API key before showing anything would be a poor trade for someone who has not
/// yet decided whether the app is worth signing up for.
struct WelcomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: "wineglass")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)

                Text("Ullage")
                    .font(.largeTitle.weight(.semibold))

                Text("Photograph a wine label. Ullage recognises the bottle, researches it online, and tells you where it's from, what the winemaker says about it, and when to drink it.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                point(
                    "text.viewfinder",
                    "Reads, doesn't scan",
                    "A vision model looks at the whole bottle instead of running OCR, so worn and unusual labels still work."
                )
                point(
                    "magnifyingglass",
                    "Researches every bottle",
                    "It searches the producer's own pages and critics, and shows you the searches as it makes them."
                )
                point(
                    "checkmark.shield",
                    "Says where facts came from",
                    "Every claim is tagged as read from the label, found online, or inferred."
                )
            }
            .padding(.horizontal, 4)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    isShowingSettings = true
                } label: {
                    Text("Add an OpenAI key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)

                Button("Look around with a sample first") {
                    finish()
                }
                .font(.callout)
            }
        }
        .padding(24)
        .sheet(isPresented: $isShowingSettings, onDismiss: {
            // Adding a key is the whole point of that sheet; if one is now stored, there is
            // nothing left to welcome anybody to.
            if settings.hasAPIKey { finish() }
        }) {
            SettingsView()
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.accentLight)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        dismiss()
    }
}

#Preview {
    WelcomeView()
        .environment(AppSettings(defaults: .previewDefaults))
}
