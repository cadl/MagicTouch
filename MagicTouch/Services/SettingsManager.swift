//
//  SettingsManager.swift
//  MagicTouch
//
//  Manages user settings and persists them using UserDefaults
//

import Foundation
import Combine

// MARK: - AppLanguage

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case fr = "fr"
    case es = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "settings.language.system")
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .es: return "Español"
        }
    }

    var languageCode: String? {
        self == .system ? nil : rawValue
    }
}

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

    @Published var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Keys.selectedLanguage)
            applyLanguage()
        }
    }

    // MARK: - Constants

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let clickMode = "clickMode"
        static let launchAtLogin = "launchAtLogin"
        static let selectedLanguage = "selectedLanguage"
    }

    private enum Defaults {
        static let isEnabled = true
        static let clickMode = ClickMode.leftRight
        static let launchAtLogin = false
        static let selectedLanguage = AppLanguage.system
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

        // Load language preference
        if let languageString = UserDefaults.standard.string(forKey: Keys.selectedLanguage),
           let language = AppLanguage(rawValue: languageString) {
            self.selectedLanguage = language
        } else {
            self.selectedLanguage = Defaults.selectedLanguage
        }

        // Apply language on startup
        applyLanguage()
    }

    // MARK: - Public Methods

    /// Reset all settings to defaults
    func resetToDefaults() {
        isEnabled = Defaults.isEnabled
        clickMode = Defaults.clickMode
        launchAtLogin = Defaults.launchAtLogin
        selectedLanguage = Defaults.selectedLanguage
    }

    // MARK: - Private Methods

    /// Apply the selected language to the app
    private func applyLanguage() {
        if let languageCode = selectedLanguage.languageCode {
            UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}
