import SwiftUI
import UllageCore
import UIKit

/// Where the OpenAI API key is entered, checked and stored.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draftKey = ""
    @State private var isEditingKey = false
    @State private var verification: AppSettings.KeyVerification?
    @State private var isVerifying = false
    @State private var isConfirmingRemoval = false
    @State private var saveError: String?

    private let apiKeysURL = URL(string: "https://platform.openai.com/api-keys")!

    var body: some View {
        NavigationStack {
            Form {
                keySection

                if settings.hasAPIKey {
                    modelSection
                    removalSection
                }

                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't save the key", isPresented: .constant(saveError != nil)) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog(
                "Remove the stored key?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove key", role: .destructive) { removeKey() }
            } message: {
                Text("Ullage will go back to demo mode and stop making real requests.")
            }
        }
    }

    // MARK: - Key

    @ViewBuilder
    private var keySection: some View {
        Section {
            if let masked = settings.maskedKey, !isEditingKey {
                storedKeyRow(masked)
            } else {
                keyEntryRow
            }
        } header: {
            Text("OpenAI API key")
        } footer: {
            keyFooter
        }
    }

    private func storedKeyRow(_ masked: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(masked)
                        .font(.body.monospaced())
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Theme.accentLight)
                }
                Spacer()
                Button("Replace") {
                    // Start from empty rather than seeding the field with the masked value:
                    // editing a masked key in place is how a stored key gets corrupted into
                    // literal bullet characters.
                    draftKey = ""
                    verification = nil
                    isEditingKey = true
                }
                .font(.footnote)
            }

            if let verification, verification.isSuccess {
                verificationRow(verification)
            }

            Button {
                Task { await verifyStoredKey() }
            } label: {
                if isVerifying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                } else {
                    Text("Check this key still works")
                }
            }
            .font(.footnote)
            .disabled(isVerifying)
        }
    }

    private var keyEntryRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SecureField("sk-…", text: $draftKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .onSubmit { Task { await verifyAndSave() } }

                // Typing a 164-character key on a phone keyboard is not a thing anyone should
                // be asked to do.
                Button {
                    if let pasted = UIPasteboard.general.string {
                        draftKey = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        verification = nil
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .disabled(!UIPasteboard.general.hasStrings)
            }

            if let verification {
                verificationRow(verification)
            }

            HStack {
                Button {
                    Task { await verifyAndSave() }
                } label: {
                    if isVerifying {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Text("Verify and save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(draftKey.isEmpty || isVerifying)

                if settings.hasAPIKey {
                    Button("Cancel") {
                        draftKey = ""
                        verification = nil
                        isEditingKey = false
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private func verificationRow(_ result: AppSettings.KeyVerification) -> some View {
        Label {
            Text(result.message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .foregroundStyle(result.isSuccess ? .green : .orange)
    }

    @ViewBuilder
    private var keyFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.isInDemoMode {
                Text("Without a key Ullage runs in demo mode: it shows one sample wine and makes no requests.")
            }
            Text("The key is kept in the device keychain, never leaves this phone except to call OpenAI, and is not included in backups. Scans are billed to your own OpenAI account.")
            Link("Create a key on platform.openai.com", destination: apiKeysURL)
                .font(.footnote)
        }
    }

    // MARK: - Models

    private var modelSection: some View {
        Section {
            Picker("Depth", selection: Binding(
                get: { Preset(configuration: settings.configuration) },
                set: { settings.configuration = $0.configuration(keeping: settings.configuration) }
            )) {
                ForEach(Preset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Toggle("Search the web", isOn: Binding(
                get: { settings.configuration.enableWebSearch },
                set: { settings.configuration.enableWebSearch = $0 }
            ))
        } header: {
            Text("Research")
        } footer: {
            Text(settings.configuration.enableWebSearch
                 ? "Ullage looks up each bottle online, which is slower and costs more but is the only way to get the producer's own notes and real critic scores."
                 : "With search off, Ullage answers from the model's own knowledge alone. Faster and cheaper, but it cannot cite anything and will be wrong more often about specific vintages.")
        }
    }

    /// A choice between two named configurations rather than a raw model picker: the model
    /// names mean nothing to most people, and the real question is how much to spend.
    private enum Preset: Hashable, CaseIterable {
        case thorough
        case quick

        init(configuration: ModelConfiguration) {
            self = configuration.researchModel == ModelConfiguration.default.researchModel ? .thorough : .quick
        }

        var title: String {
            switch self {
            case .thorough: return "Thorough"
            case .quick: return "Quick"
            }
        }

        func configuration(keeping current: ModelConfiguration) -> ModelConfiguration {
            var base = self == .thorough ? ModelConfiguration.default : ModelConfiguration.economical
            base.enableWebSearch = current.enableWebSearch
            return base
        }
    }

    // MARK: - Removal and about

    private var removalSection: some View {
        Section {
            Button("Remove key", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.shortVersion)
        } footer: {
            Text("Ullage reads labels with a vision model rather than OCR, then researches each bottle on the web. Everything it tells you is tagged with where it came from — tap any badge to see the source.")
        }
    }

    // MARK: - Actions

    private func verifyAndSave() async {
        isVerifying = true
        defer { isVerifying = false }

        let result = await settings.verify(key: draftKey)
        verification = result

        // A rate-limited key is a working key; refusing to save it would be perverse.
        let isUsable: Bool
        if case .rateLimited = result {
            isUsable = true
        } else {
            isUsable = result.isSuccess
        }
        guard isUsable else { return }

        do {
            try settings.saveAPIKey(draftKey)
            draftKey = ""
            isEditingKey = false
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func verifyStoredKey() async {
        isVerifying = true
        defer { isVerifying = false }
        // Verifying what is stored, not what is typed, so this checks the real thing.
        verification = await settings.verifyStoredKey()
    }

    private func removeKey() {
        do {
            try settings.removeAPIKey()
            draftKey = ""
            verification = nil
            isEditingKey = false
        } catch {
            saveError = error.localizedDescription
        }
    }
}

extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview("No key") {
    SettingsView()
        .environment(AppSettings(defaults: .previewDefaults))
}
