import Foundation
import IOKit

/// Observe the same HID services used to identify the multitouch devices.
/// Both notifications are drained on the main queue before asking for a rescan.
final class DeviceConnectionMonitor {
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, notification, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                { context, iterator in
                    guard let context else { return }
                    let monitor = Unmanaged<DeviceConnectionMonitor>.fromOpaque(context).takeUnretainedValue()
                    if DeviceConnectionMonitor.drain(iterator) { monitor.onChange() }
                }, context, &iterator
            )
            if result == KERN_SUCCESS {
                iterators.append(iterator)
                // Arm notifications without treating the initial inventory as a change.
                _ = Self.drain(iterator)
            } else {
                NSLog("MagicTouch: Device notification registration failed: %d", result)
            }
        }
    }

    private static func drain(_ iterator: io_iterator_t) -> Bool {
        var changed = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            changed = true
            IOObjectRelease(service)
        }
        return changed
    }

    deinit {
        if let port { IONotificationPortSetDispatchQueue(port, nil) }
        for iterator in iterators { IOObjectRelease(iterator) }
        if let port { IONotificationPortDestroy(port) }
    }
}
