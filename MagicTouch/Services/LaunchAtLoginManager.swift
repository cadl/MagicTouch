//
//  LaunchAtLoginManager.swift
//  MagicTouch
//
//  Manages launch at login functionality using SMAppService
//

import Foundation
import ServiceManagement

class LaunchAtLoginManager {

    // MARK: - Singleton

    static let shared = LaunchAtLoginManager()

    private init() {}

    // MARK: - Public Methods

    /// Set launch at login status
    func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                        print("Launch at login enabled")
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        print("Launch at login disabled")
                    }
                }
            } catch {
                print("Failed to set launch at login: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions
            print("Launch at login requires macOS 13.0+")
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
