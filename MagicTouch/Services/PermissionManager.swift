//
//  PermissionManager.swift
//  MagicTouch
//
//  Manages accessibility permissions required for the app
//

import Cocoa
import Combine

class PermissionManager: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var hasAccessibilityPermission = false

    // MARK: - Singleton

    static let shared = PermissionManager()

    // MARK: - Private Properties

    private var timer: Timer?

    // MARK: - Initialization

    private init() {
        checkPermission()
        startMonitoring()
    }

    // MARK: - Public Methods

    /// Check if accessibility permission is granted
    func checkPermission() {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
        }
    }

    /// Request accessibility permission (will show system prompt)
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
        }
    }

    /// Open System Settings to Accessibility privacy pane
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Stop monitoring permissions
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private Methods

    private func startMonitoring() {
        // Check permission status every 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
    }

    deinit {
        stopMonitoring()
    }
}
