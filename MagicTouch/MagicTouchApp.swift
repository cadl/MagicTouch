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
        // Settings window
        WindowGroup(id: "settings") {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        multitouchManager.updateSettings(enabled: settings.isEnabled, clickMode: settings.clickMode)

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        multitouchManager.stop()
    }

    // Show settings window
    private func showSettingsWindow() {
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // Find and show settings window, or create a new one
        let windows = NSApp.windows.filter { !$0.isSheet }
        if let window = windows.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            // If no window exists, create a new one by opening the URL
            if let url = URL(string: "magictouch://settings") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func setupWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                NSLog("MagicTouch: 💤 System will sleep; stopping multitouch monitoring")
                self.multitouchManager.stop()
            }
        )

        workspaceObservers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                NSLog("MagicTouch: 🌅 System did wake; restarting multitouch monitoring")
                guard self.permissionManager.hasAccessibilityPermission else { return }
                self.multitouchManager.restart(reason: "systemDidWake")
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
