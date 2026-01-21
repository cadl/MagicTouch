//
//  MultitouchManager.swift
//  MagicTouch
//
//  Manages multitouch events from Magic Mouse and coordinates tap detection
//

import Foundation
import Cocoa
import Combine

// MARK: - Touch Callback Bridge

/// Global weak reference for callback
private weak var globalManagerInstance: MultitouchManager?

/// C callback function that receives touch events
private func multitouchCallback(
    device: Int32,
    data: UnsafeMutablePointer<MTTouch>?,
    numFingers: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard let manager = globalManagerInstance,
          let touchData = data else {
        return 0
    }

    // Convert C array to Swift array
    var touches: [MTTouch] = []
    for i in 0..<Int(numFingers) {
        touches.append(touchData[i])
    }

    // Process touches on main thread
    DispatchQueue.main.async {
        manager.processTouches(touches, timestamp: timestamp)
    }

    return 0
}

// MARK: - Multitouch Manager

class MultitouchManager: ObservableObject {

    // MARK: - Singleton

    static let shared = MultitouchManager()

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var magicMouseConnected = false

    // MARK: - Private Properties

    private var devices: [UnsafeMutableRawPointer] = []
    private var pendingRestartWorkItem: DispatchWorkItem?
    private var tapDetector = TapDetector(
        tapTimeThreshold: TouchConfiguration.tapTimeThreshold,
        tapMovementThreshold: TouchConfiguration.tapMovementThreshold
    )
    private var clickSequenceTracker = ClickSequenceTracker()
    private var cursorPositionAtTouchStart: CGPoint?
    private var touchStartPosition: MTPoint?
    private var lastScrollLikeTime: TimeInterval = 0
    private var currentTouchStartTimestamp: TimeInterval?

    // Settings
    private var isEnabled = true
    private var clickMode: ClickMode = .leftRight // left side = left, right side = right

    // MARK: - Initialization

    init() {
        globalManagerInstance = self
    }

    // MARK: - Public Methods

    /// Start monitoring Magic Mouse devices
    func start() {
        guard !isRunning else { return }

        // Discover multitouch devices
        guard let deviceListUnmanaged = MTDeviceCreateList() else {
            NSLog("MagicTouch: ❌ Failed to create device list")
            return
        }

        let deviceList = deviceListUnmanaged.takeRetainedValue() as CFArray
        let count = CFArrayGetCount(deviceList)
        NSLog("MagicTouch: 📱 Found %ld multitouch device(s)", count)
        devices.removeAll()

        for i in 0..<count {
            if let devicePtr = CFArrayGetValueAtIndex(deviceList, i) {
                let mutableDevicePtr = UnsafeMutableRawPointer(mutating: devicePtr)

                let isBuiltIn = MTDeviceIsBuiltIn(mutableDevicePtr)

                // Get device info for logging and filtering
                let deviceInfo = DeviceIdentifier.getDeviceInfo(from: mutableDevicePtr)

                NSLog("MagicTouch:    Device %ld: isBuiltIn=%@, vendorID=0x%04X, productID=0x%04X, name=%@",
                      i,
                      isBuiltIn ? "YES" : "NO",
                      deviceInfo?.vendorID ?? 0,
                      deviceInfo?.productID ?? 0,
                      deviceInfo?.productName ?? "Unknown")

                // Only accept non-built-in devices that are Magic Mouse
                if !isBuiltIn {
                    if let info = deviceInfo, info.isMagicMouse {
                        NSLog("MagicTouch: ✅ Found Magic Mouse: %@", info.productName ?? "Unknown")
                        devices.append(mutableDevicePtr)

                        // Register callback
                        MTRegisterContactFrameCallback(mutableDevicePtr, multitouchCallback)

                        // Start device
                        MTDeviceStart(mutableDevicePtr, 0)
                    } else {
                        NSLog("MagicTouch: ⏭️  Skipping non-Magic Mouse device: %@",
                              deviceInfo?.productName ?? "Unknown (vendorID=0x\(String(format: "%04X", deviceInfo?.vendorID ?? 0)))")
                    }
                }
            }
        }

        isRunning = !devices.isEmpty
        magicMouseConnected = !devices.isEmpty

        NSLog("MagicTouch: MultitouchManager started with %ld device(s)", devices.count)
    }

    /// Stop then start again (coalesced), useful after sleep/wake or device reconnect.
    func restart(reason: String, initialDelay: TimeInterval = 1.0, retryDelay: TimeInterval = 2.0) {
        pendingRestartWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSLog("MagicTouch: 🔄 Restart requested (%@)", reason)

            self.stop()
            self.start()

            if !self.isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                    guard let self else { return }
                    if !self.isRunning {
                        NSLog("MagicTouch: 🔁 Restart retry (%@)", reason)
                        self.stop()
                        self.start()
                    }
                }
            }
        }

        pendingRestartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: workItem)
    }

    /// Stop monitoring
    func stop() {
        guard isRunning else { return }

        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil

        for device in devices {
            MTUnregisterContactFrameCallback(device, multitouchCallback)
            MTDeviceStop(device)
            MTDeviceRelease(device)
        }

        devices.removeAll()
        isRunning = false
        magicMouseConnected = false
        tapDetector.reset()
        cursorPositionAtTouchStart = nil
        touchStartPosition = nil
        lastScrollLikeTime = 0
        clickSequenceTracker.reset()
        currentTouchStartTimestamp = nil

        NSLog("MagicTouch: MultitouchManager stopped")
    }

    /// Update settings
    func updateSettings(enabled: Bool, clickMode: ClickMode) {
        let wasEnabled = isEnabled
        self.isEnabled = enabled
        self.clickMode = clickMode

        if wasEnabled && !enabled {
            lastScrollLikeTime = ProcessInfo.processInfo.systemUptime
            clickSequenceTracker.requestReset()
            tapDetector.reset()
            cursorPositionAtTouchStart = nil
            touchStartPosition = nil
            currentTouchStartTimestamp = nil
        }

        let clickModeLabel: String = switch clickMode {
        case .leftRight:
            "leftRight"
        case .leftOnly:
            "leftOnly"
        }
        NSLog("MagicTouch: Settings updated - enabled=%@, clickMode=%@",
              enabled ? "YES" : "NO", clickModeLabel)
    }

    // MARK: - Touch Processing

    fileprivate func processTouches(_ touches: [MTTouch], timestamp: Double) {
        guard isEnabled else { return }

        // Check for pending reset
        clickSequenceTracker.checkPendingReset()

        if touches.isEmpty {
            // No touches - evaluate if we had a tap
            NSLog("MagicTouch: [END] Touch ended")
            if tapDetector.isTracking {
                // Removed cursor movement check at touch end - causes issues with context menus
                // TapDetector already handles scroll detection via peak speed and displacement

                // When the frame has 0 touches, use TapDetector's last observed position.
                if let tapPosition = tapDetector.touchEnded(timestamp: timestamp) {
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastScrollLikeTime <= TouchConfiguration.scrollSuppressTapWindow {
                        let duration = timestamp - (currentTouchStartTimestamp ?? timestamp)
                        if duration <= TouchConfiguration.scrollSuppressTapMaxDuration {
                            NSLog("MagicTouch: [NO-TAP] Suppressed due to recent scroll (%.0fms) + short tap (%.0fms)",
                                  (now - lastScrollLikeTime) * 1000.0, duration * 1000.0)
                            clickSequenceTracker.requestReset()
                        } else {
                            handleTap(at: tapPosition)
                        }
                    } else {
                    handleTap(at: tapPosition)
                    }
                } else {
                    NSLog("MagicTouch: [NO-TAP] Gesture did not qualify as tap")
                }
            }
            cursorPositionAtTouchStart = nil
            touchStartPosition = nil
            currentTouchStartTimestamp = nil
            return
        }

        if touches.count == 1 {
            // Single touch
            let touch = touches[0]
            let position = touch.normalized.position
            let velocity = MTPoint(
                x: touch.normalized.velocity.x,
                y: touch.normalized.velocity.y
            )

            if !tapDetector.isTracking {
                // Touch start
                NSLog("MagicTouch: [BEGIN] Touch at (%.2f, %.2f)", position.x, position.y)
                tapDetector.touchBegan(at: position, velocity: velocity, timestamp: timestamp)
                currentTouchStartTimestamp = timestamp
                cursorPositionAtTouchStart = NSEvent.mouseLocation
                touchStartPosition = position
            } else {
                // Touch moved
                tapDetector.touchMoved(to: position, velocity: velocity)

                // Check cursor movement (only for cancelling tap, not for multi-click)
                if let startCursorPos = cursorPositionAtTouchStart {
                    let currentCursorPos = NSEvent.mouseLocation
                    let dx = currentCursorPos.x - startCursorPos.x
                    let dy = currentCursorPos.y - startCursorPos.y
                    let cursorDistance = sqrt(dx * dx + dy * dy)

                    if cursorDistance > TouchConfiguration.cursorMovementThreshold {
                        NSLog("MagicTouch: [SCROLL] Cursor movement detected (%.1fpx); cancelling", cursorDistance)
                        lastScrollLikeTime = ProcessInfo.processInfo.systemUptime
                        clickSequenceTracker.requestReset()
                        tapDetector.reset()
                        cursorPositionAtTouchStart = nil
                        touchStartPosition = nil
                        currentTouchStartTimestamp = nil
                    }
                }
            }
        } else {
            // Multiple touches - cancel tap detection
            NSLog("MagicTouch: [CANCEL] Multi-touch detected; cancelling")
            lastScrollLikeTime = ProcessInfo.processInfo.systemUptime
            clickSequenceTracker.requestReset()
            tapDetector.reset()
            cursorPositionAtTouchStart = nil
            touchStartPosition = nil
            currentTouchStartTimestamp = nil
        }
    }

    private func handleTap(at position: MTPoint) {
        // Determine click type based on touch position and mode
        let clickType: MouseClickType = switch clickMode {
        case .leftRight:
            // X > 0.6 = right side, X < 0.4 = left side
            position.x > 0.6 ? .right : .left
        case .leftOnly:
            .left
        }

        // Process click and get click state (1=single, 2=double, 3=triple)
        let clickState = clickSequenceTracker.processClick(at: position, type: clickType)

        // Log the click
        let clickLabel: String = switch clickType {
        case .left:
            "LEFT"
        case .right:
            "RIGHT"
        }
        if clickState == 3 {
            NSLog("MagicTouch: [TRIPLE] %@ click at (%.2f, %.2f)", clickLabel, position.x, position.y)
        } else if clickState > 3 {
            NSLog("MagicTouch: [MULTI %lld] %@ click at (%.2f, %.2f)", clickState, clickLabel, position.x, position.y)
        } else if clickState == 2 {
            NSLog("MagicTouch: [DOUBLE] %@ click at (%.2f, %.2f)", clickLabel, position.x, position.y)
        } else {
            NSLog("MagicTouch: [TAP] %@ click at (%.2f, %.2f)", clickLabel, position.x, position.y)
        }

        // Simulate click immediately (no delay)
        ClickSimulator.simulateClick(type: clickType, clickState: clickState)
    }

    // MARK: - Cleanup

    deinit {
        stop()
        globalManagerInstance = nil
    }
}
