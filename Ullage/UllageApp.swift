import SwiftData
import SwiftUI

@main
struct UllageApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .tint(Theme.accent)
        }
        .modelContainer(for: ScanRecord.self)
    }
}

private struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @State private var isShowingWelcome = false

    var body: some View {
        ScanView(settings: settings)
            .fullScreenCover(isPresented: $isShowingWelcome) {
                WelcomeView()
            }
            .task {
                // Only on a genuinely first launch. Someone who chose demo mode should not be
                // asked again every time they open the app.
                if !settings.hasCompletedOnboarding && !settings.hasAPIKey {
                    isShowingWelcome = true
                }
            }
    }
}

extension UserDefaults {
    /// A throwaway domain so previews never read or write the real settings.
    static var previewDefaults: UserDefaults {
        let defaults = UserDefaults(suiteName: "com.ullage.previews") ?? .standard
        defaults.removePersistentDomain(forName: "com.ullage.previews")
        return defaults
    }
}
