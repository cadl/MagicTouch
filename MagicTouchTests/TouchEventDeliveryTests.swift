import Cocoa
import Testing
@testable import MagicTouch

struct TouchEventDeliveryTests {
    @Test @MainActor func framesArriveInsideMenuTrackingLoop() async {
        await verifyDelivery(in: .eventTracking)
    }

    @Test @MainActor func framesArriveInsideModalPanelLoop() async {
        await verifyDelivery(in: .modalPanel)
    }

    @MainActor private func verifyDelivery(in mode: RunLoop.Mode) async {
        let delivered: Bool = await withCheckedContinuation { continuation in
            // Model opening a menu from a main-queue task: another main-queue
            // async block cannot run until this nested event loop returns.
            DispatchQueue.main.async {
                var received = false
                let deadline = Date(timeIntervalSinceNow: 0.5)
                let keepAlive = Timer(fire: deadline, interval: 0, repeats: false) { _ in }
                RunLoop.main.add(keepAlive, forMode: mode)
                TouchEventDelivery.enqueue { received = true }
                while !received && Date() < deadline {
                    _ = RunLoop.main.run(mode: mode, before: deadline)
                }
                keepAlive.invalidate()
                continuation.resume(returning: received)
            }
        }
        #expect(delivered)
    }
}
