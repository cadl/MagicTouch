//
//  LaunchAtLoginManager.swift
//  MagicTouch
//
//  Manages launch at login functionality using SMAppService
//

import Foundation
import ServiceManagement
import AppKit

class LaunchAtLoginManager {

    // MARK: - Singleton

    static let shared = LaunchAtLoginManager()

    private init() {}

    // MARK: - Public Methods

    /// Set launch at login status
    /// Returns true if successful, false otherwise
    @discardableResult
    func setLaunchAtLogin(enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            Logger.info("SMAppService current status: \(SMAppService.mainApp.status.rawValue)", category: Logger.settings)
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                        Logger.info("✓ Launch at login enabled successfully", category: Logger.settings)
                        return true
                    } else if SMAppService.mainApp.status == .enabled {
                        Logger.info("Launch at login already enabled", category: Logger.settings)
                        return true
                    } else if SMAppService.mainApp.status == .requiresApproval {
                        Logger.info("⚠️ Launch at login requires user approval in System Settings", category: Logger.settings)
                        // Open System Settings to Login Items
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                        return false
                    } else {
                        Logger.info("Launch at login status: \(SMAppService.mainApp.status.rawValue)", category: Logger.settings)
                        return false
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        Logger.info("✓ Launch at login disabled successfully", category: Logger.settings)
                        return true
                    } else {
                        Logger.info("Launch at login already disabled", category: Logger.settings)
                        return true
                    }
                }
            } catch {
                Logger.error("❌ Failed to set launch at login: \(error.localizedDescription)", category: Logger.settings)
                Logger.error("Error details: \(error)", category: Logger.settings)
                return false
            }
        } else {
            // Fallback for older macOS versions
            Logger.info("Launch at login requires macOS 13.0+", category: Logger.settings)
            return false
        }
    }

    /// Check if launch at login is enabled
    func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
