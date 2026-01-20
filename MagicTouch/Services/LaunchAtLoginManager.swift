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
            print("SMAppService current status: \(SMAppService.mainApp.status.rawValue)")
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                        print("✓ Launch at login enabled successfully")
                        return true
                    } else if SMAppService.mainApp.status == .enabled {
                        print("Launch at login already enabled")
                        return true
                    } else if SMAppService.mainApp.status == .requiresApproval {
                        print("⚠️ Launch at login requires user approval in System Settings")
                        // Open System Settings to Login Items
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                        return false
                    } else {
                        print("Launch at login status: \(SMAppService.mainApp.status.rawValue)")
                        return false
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        print("✓ Launch at login disabled successfully")
                        return true
                    } else {
                        print("Launch at login already disabled")
                        return true
                    }
                }
            } catch {
                print("❌ Failed to set launch at login: \(error.localizedDescription)")
                print("Error details: \(error)")
                return false
            }
        } else {
            // Fallback for older macOS versions
            print("Launch at login requires macOS 13.0+")
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
