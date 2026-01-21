//
//  TouchConfiguration.swift
//  MagicTouch
//
//  Touch detection configuration parameters
//

import Foundation

struct TouchConfiguration {

    // MARK: - Tap Detection Thresholds

    /// Maximum duration for a touch to be considered a tap (seconds)
    static let tapTimeThreshold: TimeInterval = 0.25

    /// Maximum movement distance for a touch to be considered a tap (normalized units)
    static let tapMovementThreshold: Float = 0.08

    // MARK: - Scroll Detection Thresholds

    /// Surface movement threshold to distinguish tap from scroll
    static let surfaceMovementThreshold: Float = 0.15

    /// Larger movement threshold for scroll detection
    static let scrollDetectionThreshold: Float = 0.2

    /// High instantaneous velocity threshold indicating a scroll flick
    static let scrollVelocityThreshold: Float = 15.0

    /// Time window to suppress tap after scroll-like gesture (seconds)
    static let scrollSuppressTapWindow: TimeInterval = 0.02

    /// Maximum tap duration for scroll suppression to apply (seconds)
    static let scrollSuppressTapMaxDuration: TimeInterval = 0.02

    // MARK: - Cursor Movement Thresholds

    /// Cursor movement threshold to cancel tap detection (pixels)
    static let cursorMovementThreshold: CGFloat = 5.0
}
