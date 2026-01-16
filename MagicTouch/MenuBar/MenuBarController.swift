//
//  MenuBarController.swift
//  MagicTouch
//
//  Manages the menu bar icon and menu
//

import Cocoa
import SwiftUI

class MenuBarController {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var settings: SettingsManager
    private var multitouchManager: MultitouchManager
    private var permissionManager: PermissionManager

    // Callback to show settings window
    var onShowSettings: (() -> Void)?

    // MARK: - Initialization

    init(settings: SettingsManager, multitouchManager: MultitouchManager, permissionManager: PermissionManager) {
        self.settings = settings
        self.multitouchManager = multitouchManager
        self.permissionManager = permissionManager
    }

    // MARK: - Public Methods

    func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set icon
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "MagicTouch") {
                image.isTemplate = true
                button.image = image
            }
            button.toolTip = "MagicTouch"
        }

        // Create menu
        updateMenu()
    }

    func updateMenu() {
        let menu = NSMenu()

        // App title
        let titleItem = NSMenuItem(title: "MagicTouch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Enable/Disable toggle
        let enableItem = NSMenuItem(
            title: settings.isEnabled ? "Disable Tap-to-Click" : "Enable Tap-to-Click",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        // Status items
        let mouseStatus = NSMenuItem(
            title: multitouchManager.magicMouseConnected ? "✓ Magic Mouse Connected" : "✗ Magic Mouse Not Found",
            action: nil,
            keyEquivalent: ""
        )
        mouseStatus.isEnabled = false
        menu.addItem(mouseStatus)

        let permissionStatus = NSMenuItem(
            title: permissionManager.hasAccessibilityPermission ? "✓ Accessibility Permission" : "✗ Accessibility Permission Required",
            action: permissionManager.hasAccessibilityPermission ? nil : #selector(requestPermission),
            keyEquivalent: ""
        )
        permissionStatus.target = self
        menu.addItem(permissionStatus)

        menu.addItem(NSMenuItem.separator())

        // Open settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit MagicTouch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Menu Actions

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        multitouchManager.updateSettings(
            enabled: settings.isEnabled,
            clickMode: settings.clickMode
        )
        if settings.isEnabled && permissionManager.hasAccessibilityPermission {
            multitouchManager.restart(reason: "menuToggleEnabled", initialDelay: 0.2)
        }
        updateMenu()
    }

    @objc private func requestPermission() {
        permissionManager.requestPermission()
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
