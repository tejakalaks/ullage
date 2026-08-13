import Foundation
import Observation
import UllageCore

/// App-wide configuration: the API key and which models to use.
///
/// The key lives in the Keychain; only a masked form is held in memory for display. Everything
/// else is small enough for `UserDefaults`.
@Observable
final class AppSettings {
    private let keychain: KeychainStore
    private let defaults: UserDefaults

    /// Present when a key is stored. Kept private so no view can accidentally render it.
    private var apiKey: String?

    private(set) var maskedKey: String?

    var configuration: ModelConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            persistConfiguration()
        }
    }

    /// Set once the user has seen the welcome screen, so it does not reappear on every launch
    /// for someone who is happy in demo mode.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded) }
    }

    init(keychain: KeychainStore = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)

        if let data = defaults.data(forKey: Keys.configuration),
           let stored = try? JSONDecoder().decode(ModelConfiguration.self, from: data) {
            self.configuration = stored
        } else {
            self.configuration = .default
        }

        let stored = keychain.string(for: .openAIAPIKey)
        self.apiKey = stored
        self.maskedKey = stored.map(Self.mask)
    }

    var hasAPIKey: Bool { apiKey?.isEmpty == false }

    /// True when the app is running on sample data because no key is set.
    var isInDemoMode: Bool { !hasAPIKey }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.set(trimmed, for: .openAIAPIKey)
        apiKey = trimmed.isEmpty ? nil : trimmed
        maskedKey = apiKey.map(Self.mask)
    }

    func removeAPIKey() throws {
        try keychain.remove(.openAIAPIKey)
        apiKey = nil
        maskedKey = nil
    }

    /// The service the scan flow should use: the real one when there is a key, the sample
    /// replay when there is not. Routing here rather than at the call site means an absent key
    /// degrades to a working demo instead of an error part-way through a scan.
    func makeIntelligenceService() -> WineIntelligenceService {
        guard let apiKey else { return MockWineIntelligence() }
        return OpenAIWineIntelligence(apiKey: apiKey, configuration: configuration)
    }

    /// Checks a key against the API without storing it.
    func verify(key: String) async -> KeyVerification {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.hasPrefix("sk-") else { return .malformed }
        do {
            try await ResponsesClient(apiKey: trimmed).verifyKey()
            return .valid
        } catch let error as ResponsesError {
            switch error {
            case .unauthorized: return .rejected
            case let .rateLimited(retryAfter): return .rateLimited(retryAfter: retryAfter)
            default: return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Re-checks the key that is actually stored, which is what the user cares about when they
    /// ask whether their key still works.
    func verifyStoredKey() async -> KeyVerification {
        guard let apiKey else { return .empty }
        return await verify(key: apiKey)
    }

    enum KeyVerification: Equatable {
        case empty
        case malformed
        case valid
        case rejected
        case rateLimited(retryAfter: TimeInterval?)
        case failed(String)

        var isSuccess: Bool { self == .valid }

        var message: String {
            switch self {
            case .empty:
                return "Enter a key first."
            case .malformed:
                return "OpenAI keys begin with \"sk-\". Check you pasted the whole thing."
            case .valid:
                return "Key works."
            case .rejected:
                return "OpenAI rejected this key."
            case let .rateLimited(retryAfter):
                if let retryAfter {
                    return "The key is valid but rate limited. Try again in \(Int(retryAfter.rounded()))s."
                }
                return "The key is valid but currently rate limited."
            case let .failed(message):
                return message
            }
        }
    }

    /// Shows enough of the key to recognise which one it is, and no more.
    static func mask(_ key: String) -> String {
        guard key.count > 11 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "\(key.prefix(7))…\(key.suffix(4))"
    }

    private func persistConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Keys.configuration)
    }

    private enum Keys {
        static let configuration = "model-configuration"
        static let onboarded = "has-completed-onboarding"
    }
}
