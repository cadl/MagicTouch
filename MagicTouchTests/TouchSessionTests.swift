import Testing
@testable import MagicTouch

struct TouchSessionTests {
    @Test func multiTouchTailDoesNotBecomeATap() {
        var gate = TouchGestureGate()
        let detector = TapDetector()
        let position = MTPoint(x: 0.5, y: 0.5)
        let velocity = MTPoint(x: 0, y: 0)
        var clicks = 0
        for (count, timestamp) in [(2, 1.0), (1, 1.02), (0, 1.08), (1, 2.0), (0, 2.06)] {
            guard gate.accepts(touchCount: count) else {
                detector.reset()
                continue
            }
            if count == 1 {
                detector.touchBegan(at: position, velocity: velocity, timestamp: timestamp)
            } else if detector.touchEnded(timestamp: timestamp) != nil {
                clicks += 1
            }
        }
        // Only the fresh single-finger gesture is a click.
        #expect(clicks == 1)
    }

    @Test func cursorMovementCancellationLastsUntilAllFingersLift() {
        var gate = TouchGestureGate()
        let initial = gate.accepts(touchCount: 1)
        #expect(initial)
        gate.cancel()
        let rejected = [1, 2, 1, 0].map { gate.accepts(touchCount: $0) }
        #expect(rejected == [false, false, false, false])
        let freshGesture = [1, 0].map { gate.accepts(touchCount: $0) }
        #expect(freshGesture == [true, true])
    }

    @Test func stopRejectsAlreadyQueuedFramesAndClicks() {
        var session = MonitoringSession()
        session.begin()
        let queuedGeneration = session.generation
        #expect(session.accepts(queuedGeneration))
        session.end()
        #expect(!session.accepts(queuedGeneration))
        #expect(!session.accepts(session.generation))
    }

    @Test func restartingDoesNotAcceptPreviousSessionEvents() {
        var session = MonitoringSession()
        session.begin()
        let previousGeneration = session.generation
        session.end()
        session.begin()
        #expect(!session.accepts(previousGeneration))
        #expect(session.accepts(session.generation))
    }

    @Test func emptyFrameWithNullPointerEndsTouch() {
        let detector = TapDetector()
        detector.touchBegan(at: MTPoint(x: 0.5, y: 0.5), velocity: MTPoint(x: 0, y: 0), timestamp: 0)
        let frame = TouchFrame.copy(data: nil, count: 0)
        #expect(frame?.isEmpty == true)
        if frame?.isEmpty == true {
            #expect(detector.touchEnded(timestamp: 0.06) != nil)
        }
    }

    @Test func malformedFramesAreNotTreatedAsTouchEnd() {
        #expect(TouchFrame.copy(data: nil, count: 1) == nil)
        #expect(TouchFrame.copy(data: nil, count: -1) == nil)
    }
}
