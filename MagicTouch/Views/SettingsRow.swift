//
//  SettingsRow.swift
//  MagicTouch
//
//  Settings row component
//

import SwiftUI

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            content
        }
        .padding(.vertical, 4)
    }
}
