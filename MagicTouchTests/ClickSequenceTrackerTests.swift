//
//  ClickSequenceTrackerTests.swift
//  MagicTouchTests
//
//  Tests for ClickSequenceTracker
//

import Testing
@testable import MagicTouch

struct ClickSequenceTrackerTests {

    // MARK: - Single Click Tests

    @Test func singleClick() {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        let state = tracker.processClick(at: position, type: .left)
        #expect(state == 1)
    }

    @Test func singleClickDifferentPositions() {
        let tracker = ClickSequenceTracker()

        let state1 = tracker.processClick(at: MTPoint(x: 0.3, y: 0.5), type: .left)
        #expect(state1 == 1)

        let state2 = tracker.processClick(at: MTPoint(x: 0.7, y: 0.5), type: .left)
        #expect(state2 == 1)
    }

    // MARK: - Double Click Tests

    @Test func doubleClick() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        let state = tracker.processClick(at: position, type: .left)

        #expect(state == 2)
    }

    @Test func doubleClickWithinThreshold() async {
        let tracker = ClickSequenceTracker()

        // First click
        _ = tracker.processClick(at: MTPoint(x: 0.5, y: 0.5), type: .left)

        // Second click slightly moved (within 0.2 threshold)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state = tracker.processClick(at: MTPoint(x: 0.55, y: 0.52), type: .left)

        #expect(state == 2)
    }

    // MARK: - Triple Click Tests

    @Test func tripleClick() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state = tracker.processClick(at: position, type: .left)

        #expect(state == 3)
    }

    @Test func tripleClickResetsToSingle() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        // Build up to triple click
        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state3 = tracker.processClick(at: position, type: .left)
        #expect(state3 == 3)

        // Fourth click should reset to single
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state4 = tracker.processClick(at: position, type: .left)
        #expect(state4 == 1)
    }

    // MARK: - Click Type Tests

    @Test func differentTypeResetsSequence() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state = tracker.processClick(at: position, type: .right)

        #expect(state == 1)
    }

    @Test func rightClickDoubleClick() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        _ = tracker.processClick(at: position, type: .right)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state = tracker.processClick(at: position, type: .right)

        #expect(state == 2)
    }

    // MARK: - Position Distance Tests

    @Test func distantPositionResetsSequence() async {
        let tracker = ClickSequenceTracker()

        // First click on left side
        _ = tracker.processClick(at: MTPoint(x: 0.1, y: 0.5), type: .left)

        // Second click on right side (distance > 0.2 threshold)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state = tracker.processClick(at: MTPoint(x: 0.9, y: 0.5), type: .left)

        #expect(state == 1)
    }

    @Test func closePositionMaintainsSequence() async {
        let tracker = ClickSequenceTracker()

        // First click
        _ = tracker.processClick(at: MTPoint(x: 0.5, y: 0.5), type: .left)

        // Second click very close (distance < 0.2 threshold)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state = tracker.processClick(at: MTPoint(x: 0.51, y: 0.51), type: .left)

        #expect(state == 2)
    }

    // MARK: - Timing Tests

    @Test func slowClickResetsSequence() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        _ = tracker.processClick(at: position, type: .left)

        // Wait longer than double-click interval (usually ~500ms)
        try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms

        let state = tracker.processClick(at: position, type: .left)
        #expect(state == 1)
    }

    // MARK: - Reset Tests

    @Test func resetClearsState() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        // Build up a sequence
        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let state1 = tracker.processClick(at: position, type: .left)
        #expect(state1 == 2)

        // Reset
        tracker.reset()

        // Next click should be single
        let state2 = tracker.processClick(at: position, type: .left)
        #expect(state2 == 1)
    }

    @Test func requestResetWithGracePeriod() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        // Build up a sequence
        _ = tracker.processClick(at: position, type: .left)

        // Request reset
        tracker.requestReset()

        // Wait for grace period to expire (100ms + buffer)
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Check pending reset
        tracker.checkPendingReset()

        // Next click should be single
        let state = tracker.processClick(at: position, type: .left)
        #expect(state == 1)
    }

    @Test func clickDuringGracePeriodCancelsReset() async {
        let tracker = ClickSequenceTracker()
        let position = MTPoint(x: 0.5, y: 0.5)

        // Build up a sequence
        _ = tracker.processClick(at: position, type: .left)
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Request reset
        tracker.requestReset()

        // Click within grace period (cancels reset)
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms < 100ms grace period
        let state = tracker.processClick(at: position, type: .left)

        // Should continue sequence
        #expect(state == 2)
    }
}
