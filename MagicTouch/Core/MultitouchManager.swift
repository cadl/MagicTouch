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
    guard let manager = globalManagerInstance else {
        return 0
    }

    // 在状态队列同步检查是否可以处理，并把回调计入 drain group，
    // 以便 stop() 能等待所有正在执行的回调退出后再释放设备对象。
    let generation = manager.stateQueue.sync { () -> UInt64? in
        guard manager.session.isRunning else { return nil }
        manager.callbackDrainGroup.enter()
        return manager.session.generation
    }

    guard let generation else { return 0 }
    defer { manager.callbackDrainGroup.leave() }
    guard let touches = TouchFrame.copy(data: data, count: numFingers) else { return 0 }

    TouchEventDelivery.enqueue {
        manager.processTouches(touches, timestamp: timestamp, generation: generation)
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
    @Published private(set) var connectedDeviceInfo: DeviceInfo?

    // MARK: - Private Properties

    // 专用队列序列化所有状态访问
    fileprivate let stateQueue = DispatchQueue(label: "com.magictouch.manager.state")

    // Session state is only accessed on stateQueue.
    fileprivate var session = MonitoringSession()
    fileprivate let callbackDrainGroup = DispatchGroup()

    private var devices: [UnsafeMutableRawPointer] = []
    private var pendingRestartWorkItem: DispatchWorkItem?
    private var pendingRetryWorkItem: DispatchWorkItem?
    private var restartGeneration: UInt64 = 0
    private var gestureGate = TouchGestureGate()
    private var deviceMonitor: DeviceConnectionMonitor?
    private var tapDetector = TapDetector(
        tapTimeThreshold: TouchConfiguration.tapTimeThreshold,
        tapMovementThreshold: TouchConfiguration.tapMovementThreshold
    )
    private var clickSequenceTracker = ClickSequenceTracker()
    private var cursorPositionAtTouchStart: CGPoint?
    private var touchStartPosition: MTPoint?
    private var lastScrollLikeTime: TimeInterval = 0
    private var currentTouchStartTimestamp: TimeInterval?
    private var suppressClickSimulationUntilUptime: TimeInterval = 0

    // Settings
    private var isSuspended = false
    private var isEnabled = true
    private var clickMode: ClickMode = .leftRight // left side = left, right side = right

    // MARK: - Initialization

    init() {
        globalManagerInstance = self
        deviceMonitor = DeviceConnectionMonitor { [weak self] in
            guard let self else { return }
            self.restart(reason: "deviceConnectionChanged", initialDelay: 0.2)
        }
    }

    // MARK: - Public Methods

    /// Start monitoring Magic Mouse devices
    func start() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }

        guard isEnabled, !isSuspended, ClickSimulator.hasAccessibilityPermission() else { return }

        // 使用队列检查状态
        let canStart = stateQueue.sync { () -> Bool in
            guard !session.isRunning else { return false }
            return true
        }

        guard canStart else { return }

        // 确保全局引用存在
        globalManagerInstance = self

        // Discover multitouch devices
        guard let deviceListUnmanaged = MTDeviceCreateList() else {
            NSLog("MagicTouch: ❌ Failed to create device list")
            return
        }

        let deviceList = deviceListUnmanaged.takeRetainedValue() as CFArray
        let count = CFArrayGetCount(deviceList)
        NSLog("MagicTouch: 📱 Found %ld multitouch device(s)", count)
        devices.removeAll()

        var discoveredDeviceInfo: DeviceInfo?

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
                        // CFArray 的生命周期只在本函数作用域内；如果不 retain，后续 stop() 会拿到悬空指针并崩溃。
                        let retainedDevice = Unmanaged<AnyObject>.fromOpaque(mutableDevicePtr).retain().toOpaque()
                        devices.append(retainedDevice)

                        // Save device info (only store the first device)
                        if discoveredDeviceInfo == nil {
                            discoveredDeviceInfo = info
                        }

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

        let hasDevices = !devices.isEmpty

        // 更新内部状态（在队列中）
        stateQueue.sync {
            if hasDevices { session.begin() }
        }

        // 更新 Published 属性（在主线程）
        isRunning = hasDevices
        magicMouseConnected = hasDevices
        connectedDeviceInfo = discoveredDeviceInfo

        NSLog("MagicTouch: MultitouchManager started with %ld device(s)", devices.count)
    }

    /// Stop then start again (coalesced), useful after sleep/wake or device reconnect.
    func restart(reason: String, initialDelay: TimeInterval = 1.0, retryDelay: TimeInterval = 2.0) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.restart(reason: reason, initialDelay: initialDelay, retryDelay: retryDelay) }
            return
        }

        // Prevent the "enable toggle clicks itself back off" race:
        // when restart is triggered by UI, ignore taps briefly around the restart window.
        if reason == "settingsToggleEnabled" || reason == "menuToggleEnabled" {
            let now = ProcessInfo.processInfo.systemUptime
            suppressClickSimulationUntilUptime = max(suppressClickSimulationUntilUptime, now + initialDelay + 0.05)
            NSLog("MagicTouch: Temporarily suppressing click simulation for %.0fms (%@)",
                  (suppressClickSimulationUntilUptime - now) * 1000.0, reason)
        }

        cancelPendingRestart()
        guard isEnabled, !isSuspended, ClickSimulator.hasAccessibilityPermission() else { return }
        let request = restartGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.restartGeneration == request,
                  self.isEnabled, !self.isSuspended, ClickSimulator.hasAccessibilityPermission() else { return }
            self.stopMonitoring()
            self.start()

            if !self.isRunning {
                let retry = DispatchWorkItem { [weak self] in
                    guard let self, self.restartGeneration == request,
                          self.isEnabled, !self.isSuspended, ClickSimulator.hasAccessibilityPermission(),
                          !self.isRunning else { return }
                    self.start()
                }
                self.pendingRetryWorkItem = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: retry)
            }
        }
        pendingRestartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: workItem)
    }

    func suspend() {
        isSuspended = true
        stop()
    }

    func resume() {
        isSuspended = false
        restart(reason: "systemDidWake")
    }

    private func cancelPendingRestart() {
        restartGeneration &+= 1
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil
        pendingRetryWorkItem?.cancel()
        pendingRetryWorkItem = nil
    }

    /// Stop monitoring, including requests waiting for devices to become available.
    func stop() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }
        cancelPendingRestart()
        stopMonitoring()
    }

    private func stopMonitoring() {
        // Invalidate queued touch frames and clicks even when no device was found.
        stateQueue.sync { session.end() }
        callbackDrainGroup.wait()

        for device in devices {
            MTUnregisterContactFrameCallback(device, multitouchCallback)
            MTDeviceStop(device)
            MTDeviceRelease(device)
        }
        devices.removeAll()
        tapDetector.reset()
        gestureGate.reset()
        cursorPositionAtTouchStart = nil
        touchStartPosition = nil
        lastScrollLikeTime = 0
        clickSequenceTracker.reset()
        currentTouchStartTimestamp = nil
        isRunning = false
        magicMouseConnected = false
        connectedDeviceInfo = nil
        NSLog("MagicTouch: MultitouchManager stopped")
    }

    /// Update settings
    func updateSettings(enabled: Bool, clickMode: ClickMode) {
        self.isEnabled = enabled
        self.clickMode = clickMode

        if !enabled {
            stop()
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

    fileprivate func processTouches(_ touches: [MTTouch], timestamp: Double, generation: UInt64) {
        guard isEnabled, stateQueue.sync(execute: { session.accepts(generation) }) else { return }
        guard gestureGate.accepts(touchCount: touches.count) else {
            tapDetector.reset()
            clickSequenceTracker.reset()
            cursorPositionAtTouchStart = nil
            touchStartPosition = nil
            currentTouchStartTimestamp = nil
            return
        }

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
                        gestureGate.cancel()
                        cursorPositionAtTouchStart = nil
                        touchStartPosition = nil
                        currentTouchStartTimestamp = nil
                    }
                }
            }
        }
    }

    private func handleTap(at position: MTPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        if now < suppressClickSimulationUntilUptime {
            NSLog("MagicTouch: [NO-TAP] Suppressed due to recent restart (%.0fms remaining)",
                  (suppressClickSimulationUntilUptime - now) * 1000.0)
            clickSequenceTracker.requestReset()
            return
        }

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
        let generation = stateQueue.sync { session.generation }
        ClickSimulator.simulateClick(type: clickType, clickState: clickState) { [weak self] in
            guard let self else { return false }
            return self.stateQueue.sync { self.session.accepts(generation) }
        }
    }

    // MARK: - Cleanup

    deinit {
        // 检查是否需要停止
        let needsStop = stateQueue.sync {
            return session.isRunning
        }

        if needsStop {
            stop()
        }

        // 确保清除全局引用
        globalManagerInstance = nil
    }
}
