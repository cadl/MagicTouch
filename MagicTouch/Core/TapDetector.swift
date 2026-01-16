//
//  TapDetector.swift
//  MagicTouch
//
//  Detects tap gestures and distinguishes them from scrolling movements
//

import Foundation

class TapDetector {

    // MARK: - Configuration

    /// Maximum duration for a valid tap (seconds)
    private let tapTimeThreshold: TimeInterval

    /// Minimum duration for a valid tap (seconds)
    private let tapMinimumDuration: TimeInterval

    /// Maximum allowed movement distance (normalized units, 0-1)
    private let tapMovementThreshold: Float

    /// High speed threshold - scroll if peak speed exceeds this (normalized units/second)
    private let highSpeedThreshold: Float = 1.0

    /// Medium speed threshold - requires displacement check (normalized units/second)
    private let mediumSpeedThreshold: Float = 0.5

    /// Total displacement threshold for scroll detection (normalized units)
    private let totalDisplacementThreshold: Float = 0.04

    // MARK: - State

    private var touchStartTime: TimeInterval?
    private var touchStartPosition: MTPoint?
    private var lastPosition: MTPoint?
    private var hasMovedTooMuch: Bool = false

    /// Peak velocity observed during touch
    private var peakSpeed: Float = 0

    /// Total displacement (accumulated movement)
    private var totalDisplacement: Float = 0

    // MARK: - Initialization

    init(
        tapTimeThreshold: TimeInterval = 0.3,
        tapMinimumDuration: TimeInterval = 0.01,
        tapMovementThreshold: Float = 0.08
    ) {
        self.tapTimeThreshold = tapTimeThreshold
        self.tapMinimumDuration = tapMinimumDuration
        self.tapMovementThreshold = tapMovementThreshold
    }

    // MARK: - Public Methods

    /// Call when a touch begins
    func touchBegan(at position: MTPoint, velocity: MTPoint, timestamp: TimeInterval) {
        touchStartTime = timestamp
        touchStartPosition = position
        lastPosition = position
        hasMovedTooMuch = false

        // Initialize peak speed and total displacement
        peakSpeed = hypotf(velocity.x, velocity.y)
        totalDisplacement = 0

        NSLog("TapDetector: touchBegan at (%.3f, %.3f), initial speed=%.3f", position.x, position.y, peakSpeed)
    }

    /// Call when touch moves
    func touchMoved(to position: MTPoint, velocity: MTPoint) {
        // Update peak speed
        let speed = hypotf(velocity.x, velocity.y)
        peakSpeed = max(peakSpeed, speed)

        // Accumulate total displacement
        if let last = lastPosition {
            let dx = position.x - last.x
            let dy = position.y - last.y
            let stepDisplacement = sqrtf(dx * dx + dy * dy)
            totalDisplacement += stepDisplacement
        }
        lastPosition = position

        // Check if movement from start exceeds threshold
        if let start = touchStartPosition {
            let dx = position.x - start.x
            let dy = position.y - start.y
            let distanceFromStart = sqrtf(dx * dx + dy * dy)
            if distanceFromStart > tapMovementThreshold {
                hasMovedTooMuch = true
            }
        }
    }

    /// Call when touch ends. Returns the tap position if valid tap detected
    func touchEnded(at position: MTPoint, timestamp: TimeInterval) -> MTPoint? {
        guard let startTime = touchStartTime,
              let startPosition = touchStartPosition else {
            NSLog("TapDetector: Touch ended but missing start data")
            reset()
            return nil
        }

        let duration = timestamp - startTime

        // Calculate final distance from start
        let dx = position.x - startPosition.x
        let dy = position.y - startPosition.y
        let finalDistance = sqrtf(dx * dx + dy * dy)

        // Segmented scroll detection logic
        let isLikelyScroll =
            peakSpeed > highSpeedThreshold ||  // Very high speed -> scroll
            (peakSpeed > mediumSpeedThreshold && totalDisplacement > totalDisplacementThreshold) ||  // Medium speed + displacement -> scroll
            hasMovedTooMuch  // Final distance exceeds threshold

        NSLog("TapDetector: touchEnded - peakSpeed=%.3f (high=%.3f, med=%.3f), totalDisp=%.3f (threshold=%.3f), finalDist=%.3f (threshold=%.3f)",
              peakSpeed, highSpeedThreshold, mediumSpeedThreshold, totalDisplacement, totalDisplacementThreshold, finalDistance, tapMovementThreshold)

        if isLikelyScroll {
            let reason: String
            if peakSpeed > highSpeedThreshold {
                reason = "high speed"
            } else if peakSpeed > mediumSpeedThreshold && totalDisplacement > totalDisplacementThreshold {
                reason = "medium speed + displacement"
            } else {
                reason = "moved too much"
            }
            NSLog("TapDetector: Determined as scroll - %@", reason)
            reset()
            return nil
        }

        // Check time constraints
        if duration < tapMinimumDuration || duration > tapTimeThreshold {
            NSLog("TapDetector: Invalid duration - %.3f (min=%.3f, max=%.3f)", duration, tapMinimumDuration, tapTimeThreshold)
            reset()
            return nil
        }

        // Valid tap
        NSLog("TapDetector: Valid tap detected at (%.3f, %.3f), duration=%.3f", startPosition.x, startPosition.y, duration)
        reset()
        return startPosition
    }

    /// Call when touch ends but you don't have a final position (e.g. frame has 0 touches).
    /// Uses the last observed position tracked via `touchBegan`/`touchMoved`.
    func touchEnded(timestamp: TimeInterval) -> MTPoint? {
        guard let endPosition = lastPosition else {
            NSLog("TapDetector: Touch ended but missing lastPosition")
            reset()
            return nil
        }
        return touchEnded(at: endPosition, timestamp: timestamp)
    }

    /// Reset tracking state
    func reset() {
        touchStartTime = nil
        touchStartPosition = nil
        lastPosition = nil
        hasMovedTooMuch = false
        peakSpeed = 0
        totalDisplacement = 0
    }

    /// Check if currently tracking a touch
    var isTracking: Bool {
        return touchStartTime != nil
    }
}

// MARK: - Helper Extensions

extension MTPoint {
    /// Distance from another point
    func distance(to other: MTPoint) -> Float {
        let dx = other.x - self.x
        let dy = other.y - self.y
        return sqrtf(dx * dx + dy * dy)
    }
}
