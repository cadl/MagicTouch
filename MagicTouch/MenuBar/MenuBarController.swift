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

        // Show main window
        let showItem = NSMenuItem(title: String(localized: "menu.show"), action: #selector(showSettings), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        // Enable/Disable toggle
        let enableItem = NSMenuItem(
            title: String(localized: settings.isEnabled ? "menu.disable" : "menu.enable"),
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        enableItem.target = self
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        // Status items
        let mouseStatusText: String
        if multitouchManager.magicMouseConnected {
            mouseStatusText = "✓ " + String(localized: "menu.status.mouseConnected")
        } else {
            mouseStatusText = "✗ " + String(localized: "menu.status.mouseNotFound")
        }
        let mouseStatus = NSMenuItem(
            title: mouseStatusText,
            action: nil,
            keyEquivalent: ""
        )
        mouseStatus.isEnabled = false
        menu.addItem(mouseStatus)

        let permissionStatusText: String
        if permissionManager.hasAccessibilityPermission {
            permissionStatusText = "✓ " + String(localized: "menu.status.permissionGranted")
        } else {
            permissionStatusText = "✗ " + String(localized: "menu.status.permissionRequired")
        }
        let permissionStatus = NSMenuItem(
            title: permissionStatusText,
            action: permissionManager.hasAccessibilityPermission ? nil : #selector(requestPermission),
            keyEquivalent: ""
        )
        permissionStatus.target = self
        menu.addItem(permissionStatus)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: String(localized: "menu.quit"), action: #selector(quit), keyEquivalent: "q")
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
