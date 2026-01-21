//
//  ClickSimulator.swift
//  MagicTouch
//
//  Simulates mouse clicks using CGEvent API
//

import Cocoa
import ApplicationServices

class ClickSimulator {

    // MARK: - Menu Tracking

    private static let clickQueue = DispatchQueue(label: "MagicTouch.ClickSimulator.clickQueue")

    private static var menuTrackingDepth = 0
    private static var lastMenuTrackingChangeUptime: TimeInterval = 0

    /// Setup menu tracking notifications
    static func setupMenuTracking() {
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            menuTrackingDepth += 1
            lastMenuTrackingChangeUptime = ProcessInfo.processInfo.systemUptime
            NSLog("ClickSimulator: Menu tracking began (depth=%d)", menuTrackingDepth)
        }

        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { _ in
            menuTrackingDepth = max(0, menuTrackingDepth - 1)
            lastMenuTrackingChangeUptime = ProcessInfo.processInfo.systemUptime
            NSLog("ClickSimulator: Menu tracking ended (depth=%d)", menuTrackingDepth)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if menuTrackingDepth > 0 {
                menuTrackingDepth = 0
                lastMenuTrackingChangeUptime = ProcessInfo.processInfo.systemUptime
                NSLog("ClickSimulator: App resigned active; cleared menu tracking state")
            }
        }
    }

    // MARK: - Public Methods

    /// Simulate a mouse click at the current cursor position
    static func simulateClick(type: MouseClickType, clickState: Int64 = 1) {
        guard let currentPosition = CGEvent(source: nil)?.location else {
            NSLog("ClickSimulator: ❌ Failed to read current cursor location")
            return
        }
        simulateClick(type: type, at: currentPosition, clickState: clickState)
    }

    /// Simulate a mouse click at a specific position
    static func simulateClick(type: MouseClickType, at position: CGPoint, clickState: Int64 = 1) {
        // If menu tracking got stuck (missed end notification), don't permanently force AX clicks.
        // Also, a tracked menu implies our app is active; if we're not active, clear the state.
        if menuTrackingDepth > 0 && !NSApp.isActive {
            menuTrackingDepth = 0
            lastMenuTrackingChangeUptime = ProcessInfo.processInfo.systemUptime
            NSLog("ClickSimulator: Cleared stale menu tracking state while app inactive")
        }

        let nowUptime = ProcessInfo.processInfo.systemUptime
        if menuTrackingDepth > 0 && nowUptime - lastMenuTrackingChangeUptime > 30.0 {
            menuTrackingDepth = 0
            lastMenuTrackingChangeUptime = nowUptime
            NSLog("ClickSimulator: Cleared stale menu tracking state after timeout")
        }

        let shouldUseAccessibilityClick = menuTrackingDepth > 0

        // Normal CGEvent-based click
        let mouseButton: CGMouseButton
        let mouseDownType: CGEventType
        let mouseUpType: CGEventType

        switch type {
        case .left:
            mouseButton = .left
            mouseDownType = .leftMouseDown
            mouseUpType = .leftMouseUp
        case .right:
            mouseButton = .right
            mouseDownType = .rightMouseDown
            mouseUpType = .rightMouseUp
        }

        clickQueue.async {
            if shouldUseAccessibilityClick {
                NSLog("ClickSimulator: Menu active, using Accessibility click")
                performAccessibilityClick(at: position)
                return
            }

            // Create mouse down event
            guard let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseDownType,
                mouseCursorPosition: position,
                mouseButton: mouseButton
            ) else {
                return
            }
            mouseDown.setIntegerValueField(.mouseEventClickState, value: clickState)

            // Create mouse up event
            guard let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseUpType,
                mouseCursorPosition: position,
                mouseButton: mouseButton
            ) else {
                return
            }
            mouseUp.setIntegerValueField(.mouseEventClickState, value: clickState)

            // Post events to the system
            mouseDown.post(tap: .cghidEventTap)

            // Delay between down and up (30-50ms for more reliable recognition)
            // Some apps need longer delays to properly recognize clicks
            usleep(useconds_t(Int.random(in: 30_000...50_000)))

            mouseUp.post(tap: .cghidEventTap)

            // Log for debugging
            let typeLabel: String = switch type {
            case .left:
                "left"
            case .right:
                "right"
            }
            NSLog("ClickSimulator: Posted %@ click (state=%lld) at (%.0f, %.0f)",
                  typeLabel, clickState, position.x, position.y)
        }
    }

    // MARK: - Accessibility Click

    /// Perform click using Accessibility API (works during modal loops)
    private static func performAccessibilityClick(at screenPoint: CGPoint) {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        // Get element at screen position
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(screenPoint.x),
            Float(screenPoint.y),
            &element
        )

        if result == .success, let element = element {
            // Perform press action on the element
            let actionResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
            NSLog("ClickSimulator: Accessibility click result: %d", actionResult.rawValue)
        } else {
            NSLog("ClickSimulator: Could not find element at position (%.0f, %.0f), result: %d",
                  screenPoint.x, screenPoint.y, result.rawValue)
        }
    }

    /// Check if we have permission to post events
    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrusted() ||
               AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
