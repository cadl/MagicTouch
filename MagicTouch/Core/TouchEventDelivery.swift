import Cocoa

/// Menus and modal panels run nested event loops which may not drain the main
/// dispatch queue. Keep touch frames flowing while those loops are active.
enum TouchEventDelivery {
    static func enqueue(_ action: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.common, .eventTracking, .modalPanel], block: action)
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
