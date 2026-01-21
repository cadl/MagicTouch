//
//  AppLifecycleManager.swift
//  MagicTouch
//
//  Application lifecycle management
//

import Foundation
import Cocoa

class AppLifecycleManager {

    // MARK: - Singleton

    static let shared = AppLifecycleManager()
    private init() {}

    // MARK: - Public Methods

    /// Restart the application
    func restartApp() {
        let appPath = Bundle.main.bundleURL.path
        let relaunchScript = """
        #!/bin/bash
        sleep 0.5
        open "\(appPath)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", relaunchScript]

        do {
            try task.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            NSLog("AppLifecycleManager: Failed to restart app: \(error)")
            NSApplication.shared.terminate(nil)
        }
    }
}
