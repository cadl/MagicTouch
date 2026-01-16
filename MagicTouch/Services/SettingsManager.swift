//
//  SettingsManager.swift
//  MagicTouch
//
//  Manages user settings and persists them using UserDefaults
//

import Foundation
import Combine

class SettingsManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    @Published var clickMode: ClickMode {
        didSet {
            UserDefaults.standard.set(clickMode == .leftRight, forKey: Keys.clickMode)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
        }
    }

    // MARK: - Constants

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let clickMode = "clickMode"
        static let launchAtLogin = "launchAtLogin"
    }

    private enum Defaults {
        static let isEnabled = true
        static let clickMode = ClickMode.leftRight
        static let launchAtLogin = false
    }

    // MARK: - Singleton

    static let shared = SettingsManager()

    // MARK: - Initialization

    private init() {
        // Load settings from UserDefaults
        self.isEnabled = UserDefaults.standard.object(forKey: Keys.isEnabled) as? Bool ?? Defaults.isEnabled
        let isLeftRight = UserDefaults.standard.object(forKey: Keys.clickMode) as? Bool ?? true
        self.clickMode = isLeftRight ? .leftRight : .leftOnly
        self.launchAtLogin = UserDefaults.standard.object(forKey: Keys.launchAtLogin) as? Bool ?? Defaults.launchAtLogin
    }

    // MARK: - Public Methods

    /// Reset all settings to defaults
    func resetToDefaults() {
        isEnabled = Defaults.isEnabled
        clickMode = Defaults.clickMode
        launchAtLogin = Defaults.launchAtLogin
    }
}
