import Combine
import Foundation
import Sparkle

/// Owns Sparkle for the lifetime of the app. Sparkle persists the user's preferences.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isAvailable = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()

    private init() {}

    func start() {
        // Debug builds use a different bundle ID and must never install production updates.
        #if !DEBUG
        guard controller == nil,
              Self.hasValidConfiguration(Bundle.main.infoDictionary ?? [:]) else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        do {
            try controller.updater.start()
        } catch {
            NSLog("MagicTouch: Unable to start updater: %@", error.localizedDescription)
            return
        }
        self.controller = controller
        isAvailable = true

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observations)
        #endif
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isAvailable else { return }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    static func hasValidConfiguration(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              !feed.contains("$("),
              let key = info["SUPublicEDKey"] as? String,
              let data = Data(base64Encoded: key), data.count == 32 else { return false }
        return true
    }
}
