import Foundation

enum ClickFeedbackStyle: String, CaseIterable, Identifiable {
    case off, expandingRing, contractingRing, glow, dot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: String(localized: "feedback.off")
        case .expandingRing: String(localized: "feedback.expandingRing")
        case .contractingRing: String(localized: "feedback.contractingRing")
        case .glow: String(localized: "feedback.glow")
        case .dot: String(localized: "feedback.dot")
        }
    }
}
