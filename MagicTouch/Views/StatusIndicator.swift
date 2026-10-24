//
//  StatusIndicator.swift
//  MagicTouch
//
//  Connection/permission status indicator component
//

import SwiftUI

struct StatusIndicator: View {
    let isConnected: Bool
    let connectedText: LocalizedStringKey
    let disconnectedText: LocalizedStringKey
    var detailText: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            if let action = action, !isConnected {
                Button(action: action) {
                    Text(disconnectedText)
                }
                .buttonStyle(.link)
                .controlSize(.small)
                .font(.callout)
            } else {
                if let detail = detailText, isConnected {
                    HStack(spacing: 0) {
                        Text(connectedText)
                        Text(" (\(detail))")
                    }
                    .font(.callout)
                } else {
                    Text(isConnected ? connectedText : disconnectedText)
                        .font(.callout)
                }
            }
        }
    }
}
