//
//  MagicTouchApp.swift
//  MagicTouch
//
//  Menu bar app with settings window for Magic Mouse tap-to-click
//

import SwiftUI
import Cocoa
import Combine

@main
struct MagicTouchApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window (single window only)
        Window("MagicTouch", id: "settings") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // Managers
    private let settings = SettingsManager.shared
    private let multitouchManager = MultitouchManager.shared
    private let permissionManager = PermissionManager.shared
    private var menuBarController: MenuBarController?
    private var permissionCancellable: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance check (defensive, LSMultipleInstancesProhibited should prevent this)
        if let bundleId = Bundle.main.bundleIdentifier {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if runningApps.count > 1 {
                NSLog("MagicTouch: ⚠️ Another instance detected, activating it and terminating self")

                // Find and activate the other instance
                if let existingApp = runningApps.first(where: { $0 != NSRunningApplication.current }) {
                    existingApp.activate()
                }

                // Terminate this instance
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
                return
            }
        }

        multitouchManager.updateSettings(enabled: settings.isEnabled, clickMode: settings.clickMode)

        UpdateManager.shared.start()

        // Setup menu bar
        menuBarController = MenuBarController(
            settings: settings,
            multitouchManager: multitouchManager,
            permissionManager: permissionManager
        )
        menuBarController?.setupMenuBar()
        menuBarController?.onShowSettings = { [weak self] in
            self?.showSettingsWindow()
        }

        // Setup menu tracking for click simulation
        ClickSimulator.setupMenuTracking()

        setupWorkspaceNotifications()

        // Start monitoring if permission is granted
        if permissionManager.hasAccessibilityPermission {
            multitouchManager.start()
        }

        // Monitor permission changes
        permissionCancellable = permissionManager.$hasAccessibilityPermission
            .removeDuplicates()
            .sink { [weak self] hasPermission in
                if hasPermission {
                    self?.multitouchManager.start()
                } else {
                    self?.multitouchManager.stop()
                }
                // Update menu bar when permission changes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.menuBarController?.updateMenu()
                }
            }

        // Show settings on first launch or if permission is needed
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch || !permissionManager.hasAccessibilityPermission {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showSettingsWindow()
            }
        } else {
            // Not first launch and has permission - hide from Dock
            hideFromDock()
        }

        // Capture settings window reference after it's created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.captureSettingsWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        multitouchManager.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSLog("MagicTouch: 🔄 Application reopen requested")
        if !flag {
            showSettingsWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app: closing the window should not terminate the app
        NSLog("MagicTouch: 🚫 Window closed, but app continues running in menu bar")
        return false
    }

    // MARK: - Dock Icon Management

    // Show Dock icon
    private func showInDock() {
        NSApp.setActivationPolicy(.regular)
    }

    // Hide Dock icon
    private func hideFromDock() {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Window Management

    // Show settings window
    private func showSettingsWindow() {
        // Show Dock icon when window opens
        showInDock()

        // Wait for activation policy to take effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            // Activate the app
            NSApp.activate(ignoringOtherApps: true)

            // If we have a cached window reference, show it
            if let window = self.settingsWindow {
                window.makeKeyAndOrderFront(nil)
                return
            }

            // Otherwise, find and show settings window
            let windows = NSApp.windows.filter { !$0.isSheet }
            if let window = windows.first {
                self.settingsWindow = window
                window.delegate = self
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // Capture settings window reference
    private func captureSettingsWindow() {
        let windows = NSApp.windows.filter { !$0.isSheet }
        if let window = windows.first {
            settingsWindow = window
            window.delegate = self
        }
    }

    private func setupWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                NSLog("MagicTouch: 💤 System will sleep; stopping multitouch monitoring")
                self.multitouchManager.suspend()
            }
        )

        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                NSLog("MagicTouch: 🌅 System did wake; restarting multitouch monitoring")
                self.multitouchManager.resume()
            }
        )

        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                guard self.permissionManager.hasAccessibilityPermission else { return }
                self.multitouchManager.restart(reason: "sessionDidBecomeActive", initialDelay: 0.5)
            }
        )

        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                guard self.permissionManager.hasAccessibilityPermission else { return }
                self.multitouchManager.restart(reason: "screensDidWake", initialDelay: 0.5)
            }
        )
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == settingsWindow {
            // Hide the window instead of closing it
            sender.orderOut(nil)
            // Hide Dock icon when window closes
            hideFromDock()
            return false
        }
        return true
    }
}
