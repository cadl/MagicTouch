//
//  ContentView.swift
//  MagicTouch
//
//  Main settings window for MagicTouch app
//

import SwiftUI

struct ContentView: View {

    @StateObject private var settings = SettingsManager.shared
    @ObservedObject private var multitouchManager = MultitouchManager.shared
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var showLaunchAtLoginAlert = false
    @State private var showRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text(String(localized: "app.name"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "app.tagline"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 18) {
                SettingsSection(title: String(localized: "section.general")) {
                    SettingsRow {
                        Text(String(localized: "main.toggle.enable"))
                        Spacer()
                        Toggle("", isOn: $settings.isEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: settings.isEnabled) { _, newValue in
                                updateMultitouchSettings()
                                if newValue && permissionManager.hasAccessibilityPermission {
                                    multitouchManager.restart(reason: "settingsToggleEnabled", initialDelay: 0.2)
                                }
                            }
                    }

                    Divider()
                        .padding(.horizontal, -12)

                    SettingsRow {
                        Text(String(localized: "main.toggle.launchAtLogin"))
                        Spacer()
                        Toggle("", isOn: $settings.launchAtLogin)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: settings.launchAtLogin) { oldValue, newValue in
                                Logger.debug("Toggle changed to: \(newValue)", category: Logger.settings)
                                let success = LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                                Logger.debug("setLaunchAtLogin returned: \(success)", category: Logger.settings)

                                // Check actual status after setting
                                if #available(macOS 13.0, *) {
                                    let actualStatus = LaunchAtLoginManager.shared.isEnabled()
                                    Logger.debug("Actual launch at login status: \(actualStatus)", category: Logger.settings)
                                }

                                if !success && newValue {
                                    // If setting failed, revert the toggle
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        settings.launchAtLogin = false
                                        showLaunchAtLoginAlert = true
                                    }
                                }
                            }
                    }
                }

                SettingsSection(title: String(localized: "section.mouseConfig")) {
                    SettingsRow {
                        Text(String(localized: "settings.clickMode.label"))
                        Spacer()
                        Picker("", selection: $settings.clickMode) {
                            Text(String(localized: "main.picker.clickMode.leftRight"))
                                .tag(ClickMode.leftRight)
                            Text(String(localized: "main.picker.clickMode.leftOnly"))
                                .tag(ClickMode.leftOnly)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help(String(localized: "main.picker.clickMode.help"))
                        .frame(width: 120)
                        .onChange(of: settings.clickMode) { _, _ in
                            updateMultitouchSettings()
                        }
                    }
                }

                SettingsSection(title: String(localized: "section.languageStatus")) {
                    SettingsRow {
                        Text(String(localized: "settings.language.label"))
                        Spacer()
                        Picker("", selection: $settings.selectedLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    if showRestartAlert {
                        HStack(spacing: 8) {
                            Spacer()
                            Text(String(localized: "settings.restartRequired"))
                                .font(.caption)
                                .foregroundColor(.orange)

                            Button(String(localized: "settings.restartNow")) {
                                AppLifecycleManager.shared.restartApp()
                            }
                            .buttonStyle(.link)
                            .controlSize(.small)
                            .font(.caption)
                        }
                        .padding(.top, 2)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusIndicator(
                        isConnected: multitouchManager.magicMouseConnected,
                        connectedText: "status.mouse.connected",
                        disconnectedText: "status.mouse.notConnected"
                    )

                    StatusIndicator(
                        isConnected: permissionManager.hasAccessibilityPermission,
                        connectedText: "status.permission.ok",
                        disconnectedText: "status.permission.grant",
                        action: {
                            permissionManager.requestPermission()
                        }
                    )
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(String(localized: "main.button.quit")) {
                        NSApplication.shared.terminate(nil)
                    }

                    Button(String(localized: "main.button.minimizeToTray")) {
                        NSApp.keyWindow?.close()
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(String(localized: "alert.launchAtLogin.title"), isPresented: $showLaunchAtLoginAlert) {
            Button(String(localized: "alert.launchAtLogin.openSettings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(String(localized: "alert.launchAtLogin.cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "alert.launchAtLogin.message"))
        }
        .onAppear {
            updateMultitouchSettings()
            // Start multitouch monitoring if permission is granted
            if permissionManager.hasAccessibilityPermission {
                multitouchManager.start()
            }
        }
        .onChange(of: permissionManager.hasAccessibilityPermission) { _, hasPermission in
            // Start/stop based on permission changes
            if hasPermission {
                multitouchManager.start()
            } else {
                multitouchManager.stop()
            }
        }
        .onChange(of: settings.selectedLanguage) { _, _ in
            showRestartAlert = true
        }
    }

    private func updateMultitouchSettings() {
        multitouchManager.updateSettings(
            enabled: settings.isEnabled,
            clickMode: settings.clickMode
        )
    }
}

#Preview {
    ContentView()
}
