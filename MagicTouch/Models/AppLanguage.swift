//
//  AppLanguage.swift
//  MagicTouch
//
//  Application language configuration
//

import Foundation

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
