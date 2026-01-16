//
//  SettingsView.swift
//  MagicTouch
//
//  Main settings panel for tap-to-click configuration
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: SettingsManager
    @ObservedObject var multitouchManager: MultitouchManager
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tap-to-Click Settings")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                // Enable toggle
                Toggle("Enable Tap-to-Click", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.isEnabled) { _, newValue in
                        updateMultitouchSettings()
                        if newValue && permissionManager.hasAccessibilityPermission {
                            multitouchManager.restart(reason: "settingsToggleEnabled", initialDelay: 0.2)
                        }
                    }

                Divider()

                // Click mode
                VStack(alignment: .leading, spacing: 8) {
                    Text("Click Mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Click Mode", selection: $settings.clickMode) {
                        Text("Left side → Left click / Right side → Right click").tag(ClickMode.leftRight)
                        Text("Any position → Left click").tag(ClickMode.leftOnly)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .onChange(of: settings.clickMode) { _, _ in
                        updateMultitouchSettings()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .onAppear {
            updateMultitouchSettings()
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
    SettingsView(
        settings: SettingsManager.shared,
        multitouchManager: MultitouchManager.shared,
        permissionManager: PermissionManager.shared
    )
    .frame(width: 400)
    .padding()
}
