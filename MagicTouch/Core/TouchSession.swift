import Foundation

/// Accessed on the manager's state queue, including from the input callback.
struct MonitoringSession {
    private(set) var isRunning = false
    private(set) var generation: UInt64 = 0

    mutating func begin() {
        generation &+= 1
        isRunning = true
    }

    mutating func end() {
        generation &+= 1
        isRunning = false
    }

    func accepts(_ generation: UInt64) -> Bool {
        isRunning && self.generation == generation
    }
}

/// A cancelled gesture stays cancelled until every finger has left the surface.
struct TouchGestureGate {
    private var cancelled = false

    mutating func accepts(touchCount: Int) -> Bool {
        if touchCount > 1 { cancelled = true }
        if cancelled {
            if touchCount == 0 { cancelled = false }
            return false
        }
        return true
    }

    mutating func cancel() { cancelled = true }
    mutating func reset() { cancelled = false }
}

enum TouchFrame {
    static func copy(data: UnsafeMutablePointer<MTTouch>?, count: Int32) -> [MTTouch]? {
        guard count >= 0 else { return nil }
        if count == 0 { return [] }
        guard let data else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(count)))
    }
}
