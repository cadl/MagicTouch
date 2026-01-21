//
//  TapDetectorTests.swift
//  MagicTouchTests
//
//  Tests for TapDetector
//

import Testing
@testable import MagicTouch

struct TapDetectorTests {

    // MARK: - Valid Tap Tests

    @Test func validTapAtCenter() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
        #expect(result?.x == position.x)
        #expect(result?.y == position.y)
    }

    @Test func validTapWithMinimalMovement() {
        let detector = TapDetector()
        let startPosition = MTPoint(x: 0.5, y: 0.5)
        let endPosition = MTPoint(x: 0.52, y: 0.51)  // Very small movement
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: startPosition, velocity: velocity, timestamp: 0)
        detector.touchMoved(to: endPosition, velocity: velocity)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }

    @Test func validQuickTap() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.05)  // 50ms

        #expect(result != nil)
    }

    // MARK: - Invalid Tap Tests - Duration

    @Test func tooLongDuration() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.5)  // 500ms > 250ms threshold

        #expect(result == nil)
    }

    @Test func edgeCaseDuration() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        // Right at threshold (0.25s)
        let result = detector.touchEnded(timestamp: 0.25)

        #expect(result != nil)
    }

    // MARK: - Invalid Tap Tests - Movement

    @Test func tooMuchMovement() {
        let detector = TapDetector()
        let startPosition = MTPoint(x: 0.5, y: 0.5)
        let endPosition = MTPoint(x: 0.7, y: 0.5)  // Large movement
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: startPosition, velocity: velocity, timestamp: 0)
        detector.touchMoved(to: endPosition, velocity: velocity)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result == nil)
    }

    @Test func diagonalMovement() {
        let detector = TapDetector()
        let startPosition = MTPoint(x: 0.5, y: 0.5)
        let endPosition = MTPoint(x: 0.6, y: 0.6)  // Diagonal movement
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: startPosition, velocity: velocity, timestamp: 0)
        detector.touchMoved(to: endPosition, velocity: velocity)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result == nil)
    }

    // MARK: - Invalid Tap Tests - Velocity

    @Test func highSpeedScroll() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let highVelocity = MTPoint(x: 2.0, y: 0)  // High velocity > 1.0 threshold

        detector.touchBegan(at: position, velocity: highVelocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result == nil)
    }

    @Test func verticalScroll() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let verticalVelocity = MTPoint(x: 0, y: 3.0)  // High vertical velocity

        detector.touchBegan(at: position, velocity: verticalVelocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result == nil)
    }

    @Test func moderateVelocity() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let moderateVelocity = MTPoint(x: 0.5, y: 0.3)  // Below threshold

        detector.touchBegan(at: position, velocity: moderateVelocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }

    // MARK: - Touch Movement Tracking

    @Test func multipleMovements() {
        let detector = TapDetector()
        let startPosition = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: startPosition, velocity: velocity, timestamp: 0)
        detector.touchMoved(to: MTPoint(x: 0.51, y: 0.51), velocity: velocity)
        detector.touchMoved(to: MTPoint(x: 0.52, y: 0.52), velocity: velocity)
        detector.touchMoved(to: MTPoint(x: 0.53, y: 0.53), velocity: velocity)

        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }

    @Test func movementThenReturn() {
        let detector = TapDetector()
        let startPosition = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: startPosition, velocity: velocity, timestamp: 0)
        detector.touchMoved(to: MTPoint(x: 0.55, y: 0.5), velocity: velocity)
        detector.touchMoved(to: startPosition, velocity: velocity)  // Return to start

        let result = detector.touchEnded(timestamp: 0.1)

        // Should still be valid as final distance from start is small
        #expect(result != nil)
    }

    // MARK: - State Management Tests

    @Test func isTrackingState() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        #expect(detector.isTracking == false)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        #expect(detector.isTracking == true)

        _ = detector.touchEnded(timestamp: 0.1)
        #expect(detector.isTracking == false)
    }

    @Test func resetClearsTracking() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        #expect(detector.isTracking == true)

        detector.reset()
        #expect(detector.isTracking == false)
    }

    @Test func endWithoutBegin() {
        let detector = TapDetector()

        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result == nil)
        #expect(detector.isTracking == false)
    }

    // MARK: - Edge Position Tests

    @Test func tapAtLeftEdge() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.0, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }

    @Test func tapAtRightEdge() {
        let detector = TapDetector()
        let position = MTPoint(x: 1.0, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }

    @Test func tapAtTopEdge() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.0)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }

    @Test func tapAtBottomEdge() {
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 1.0)
        let velocity = MTPoint(x: 0, y: 0)

        detector.touchBegan(at: position, velocity: velocity, timestamp: 0)
        let result = detector.touchEnded(timestamp: 0.1)

        #expect(result != nil)
    }
}
