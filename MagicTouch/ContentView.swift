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

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("MagicTouch")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Tap-to-Click for Magic Mouse")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)

            // Settings
            SettingsView(settings: settings, multitouchManager: multitouchManager, permissionManager: permissionManager)

            // Status
            StatusView(multitouchManager: multitouchManager, permissionManager: permissionManager)

            // Launch at login
            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .padding(.horizontal)
                .onChange(of: settings.launchAtLogin) { _, newValue in
                    LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
                }

            // Bottom buttons
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.large)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 500)
        .onAppear {
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
    }
}

#Preview {
    ContentView()
}
