import AppKit
import QuartzCore

/// One reusable, click-through panel. All presentation happens on the main run loop.
final class ClickFeedbackController {
    static let shared = ClickFeedbackController()

    private var panel: NSPanel?
    private var hideTimer: Timer?

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
    }

    /// CGEvent coordinates use the top-left of the primary display as their origin.
    func show(at eventPosition: CGPoint) {
        let style = SettingsManager.shared.clickFeedbackStyle
        guard style != .off, let primaryScreen = NSScreen.screens.first else { return }
        let position = CGPoint(x: eventPosition.x, y: primaryScreen.frame.maxY - eventPosition.y)
        present(style: style, at: position)
    }

    func preview() {
        present(style: SettingsManager.shared.clickFeedbackStyle, at: NSEvent.mouseLocation)
    }

    private func present(style: ClickFeedbackStyle, at position: CGPoint) {
        hide()
        guard style != .off else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(CGPoint(x: position.x - 32, y: position.y - 32))

        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        panel.contentView?.layer = root
        let mark = CAShapeLayer()
        mark.frame = root.bounds
        let isRing = style == .expandingRing || style == .contractingRing
        let rect: CGRect = style == .dot
            ? CGRect(x: 29, y: 29, width: 6, height: 6)
            : CGRect(x: 24, y: 24, width: 16, height: 16)
        mark.path = CGPath(ellipseIn: rect, transform: nil)
        mark.fillColor = isRing ? NSColor.clear.cgColor : NSColor.white.withAlphaComponent(style == .glow ? 0.22 : 0.9).cgColor
        mark.strokeColor = isRing ? NSColor.white.withAlphaComponent(0.65).cgColor : NSColor.clear.cgColor
        mark.lineWidth = 1
        mark.shadowColor = NSColor.black.cgColor
        mark.shadowOpacity = isRing ? 0.4 : 0.65
        mark.shadowRadius = style == .glow ? 6 : 1.5
        mark.shadowOffset = .zero
        root.addSublayer(mark)

        if style == .glow {
            let glow = CAGradientLayer()
            glow.type = .radial
            glow.frame = CGRect(x: 20, y: 20, width: 24, height: 24)
            glow.colors = [NSColor.white.withAlphaComponent(0.55).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            mark.path = nil
            mark.addSublayer(glow)
        }

        let duration = 0.20
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        mark.opacity = 0
        mark.add(fade, forKey: "fade")

        if isRing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = style == .expandingRing ? 0.65 : 1.15
            scale.toValue = style == .expandingRing ? 1.25 : 0.75
            scale.duration = duration
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            mark.add(scale, forKey: "scale")
        }

        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .modalPanel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        panel.contentView?.wantsLayer = true
        return panel
    }
}
