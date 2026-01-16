//
//  StatusView.swift
//  MagicTouch
//
//  Displays device connection and permission status
//

import SwiftUI

struct StatusView: View {

    @ObservedObject var multitouchManager: MultitouchManager
    @ObservedObject var permissionManager: PermissionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                // Magic Mouse connection status
                HStack(spacing: 8) {
                    Circle()
                        .fill(multitouchManager.magicMouseConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(multitouchManager.magicMouseConnected ? "Magic Mouse Connected" : "Magic Mouse Not Found")
                        .font(.system(size: 13))
                }

                // Accessibility permission status
                HStack(spacing: 8) {
                    Circle()
                        .fill(permissionManager.hasAccessibilityPermission ? Color.green : Color.red)
                        .frame(width: 12, height: 12)

                    Text(permissionManager.hasAccessibilityPermission ? "Accessibility Permission Granted" : "Accessibility Permission Required")
                        .font(.system(size: 13))

                    if !permissionManager.hasAccessibilityPermission {
                        Button("Grant Permission") {
                            permissionManager.requestPermission()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    StatusView(
        multitouchManager: MultitouchManager.shared,
        permissionManager: PermissionManager.shared
    )
    .frame(width: 400)
    .padding()
}
