//
//  ClickSequenceTracker.swift
//  MagicTouch
//
//  Manages single/double/triple click sequence tracking
//

import Foundation
import Cocoa

class ClickSequenceTracker {

    // MARK: - Configuration

    /// Touch surface distance threshold for multi-click (normalized) - 20%
    private let multiClickSurfaceThreshold: Float = 0.2

    /// Grace period to avoid breaking click sequences on minor scrolls (seconds)
    private let clickSequenceGracePeriod: TimeInterval = 0.1

    // MARK: - State

    /// Timestamp of the last click (using system uptime)
    private var lastClickTime: TimeInterval = 0

    /// Touch surface position of the last click
    private var lastClickSurfacePosition: MTPoint?

    /// Type of the last click (left or right)
    private var lastClickType: MouseClickType?

    /// Current click sequence count (1=single, 2=double, 3=triple)
    private var clickSequenceCount: Int64 = 0

    /// Pending reset timestamp (for grace period mechanism)
    private var pendingResetTime: TimeInterval?

    // MARK: - Public Methods

    /// Process a click and return the click state (1=single, 2=double, 3=triple)
    func processClick(at position: MTPoint, type: MouseClickType) -> Int64 {
        // Cancel any pending reset since user is actively clicking
        cancelPendingReset()

        let currentTime = ProcessInfo.processInfo.systemUptime

        // Use system double-click interval preference
        let maxInterval = NSEvent.doubleClickInterval

        var clickState: Int64 = 1

        if let lastSurfacePos = lastClickSurfacePosition,
           let lastType = lastClickType {

            let timeSinceLastClick = currentTime - lastClickTime

            // Check time and type constraints
            if timeSinceLastClick <= maxInterval && type == lastType {
                // Check touch surface position distance
                let surfaceDx = position.x - lastSurfacePos.x
                let surfaceDy = position.y - lastSurfacePos.y
                let surfaceDistance = sqrtf(surfaceDx * surfaceDx + surfaceDy * surfaceDy)

                if surfaceDistance <= multiClickSurfaceThreshold {
                    // Limit clickState to maximum 3 (single, double, triple)
                    // macOS doesn't recognize clickState > 3
                    if clickSequenceCount >= 3 {
                        clickState = 1  // Reset after triple-click
                        NSLog("MagicTouch: Multi-click sequence reset after triple-click")
                    } else {
                        clickState = clickSequenceCount + 1
                    }
                    NSLog("MagicTouch: Multi-click accepted - surfaceDist=%.3f <= %.3f",
                          surfaceDistance, multiClickSurfaceThreshold)
                } else {
                    NSLog("MagicTouch: Multi-click rejected - surfaceDist=%.3f > %.3f",
                          surfaceDistance, multiClickSurfaceThreshold)
                }
            }
        }

        // Update click sequence tracking
        lastClickTime = currentTime
        lastClickSurfacePosition = position
        lastClickType = type
        clickSequenceCount = clickState

        return clickState
    }

    /// Request to reset click sequence (with grace period)
    func requestReset() {
        pendingResetTime = ProcessInfo.processInfo.systemUptime
        NSLog("MagicTouch: Click sequence reset requested (grace period: %.0fms)",
              clickSequenceGracePeriod * 1000)
    }

    /// Check and execute pending reset if grace period has expired
    func checkPendingReset() {
        guard let pendingTime = pendingResetTime else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - pendingTime > clickSequenceGracePeriod {
            NSLog("MagicTouch: Grace period expired - executing click sequence reset")
            reset()
        }
    }

    /// Immediately reset the click sequence
    func reset() {
        lastClickTime = 0
        lastClickSurfacePosition = nil
        lastClickType = nil
        clickSequenceCount = 0
        pendingResetTime = nil
    }

    // MARK: - Private Methods

    /// Cancel pending reset (because user clicked)
    private func cancelPendingReset() {
        if pendingResetTime != nil {
            NSLog("MagicTouch: Pending reset cancelled - user clicked during grace period")
            pendingResetTime = nil
        }
    }
}
