//
//  DeviceIdentifier.swift
//  MagicTouch
//
//  Utility class to identify multitouch devices using IOKit
//

import Foundation
import IOKit

// MARK: - Device Info

struct DeviceInfo {
    let vendorID: Int
    let productID: Int
    let productName: String?

    var isMagicMouse: Bool {
        // Apple Vendor ID = 0x05AC (1452)
        guard vendorID == 0x05AC else { return false }

        // Magic Mouse 1: 0x030D (781)
        // Magic Mouse 2: 0x0269 (617)
        return productID == 0x030D || productID == 0x0269
    }
}

// MARK: - Device Identifier

class DeviceIdentifier {

    /// Get device information from a multitouch device reference
    static func getDeviceInfo(from device: UnsafeMutableRawPointer) -> DeviceInfo? {
        let service = MTDeviceGetService(device)
        guard service != 0 else {
            NSLog("MagicTouch: MTDeviceGetService returned invalid service")
            return nil
        }

        // Get Vendor ID
        var vendorID: Int = 0
        if let vendorRef = IORegistryEntryCreateCFProperty(
            service,
            kIOHIDVendorIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) {
            vendorID = (vendorRef.takeRetainedValue() as? NSNumber)?.intValue ?? 0
        }

        // Get Product ID
        var productID: Int = 0
        if let productRef = IORegistryEntryCreateCFProperty(
            service,
            kIOHIDProductIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) {
            productID = (productRef.takeRetainedValue() as? NSNumber)?.intValue ?? 0
        }

        // Get Product Name
        var productName: String?
        if let nameRef = IORegistryEntryCreateCFProperty(
            service,
            kIOHIDProductKey as CFString,
            kCFAllocatorDefault,
            0
        ) {
            productName = nameRef.takeRetainedValue() as? String
        }

        return DeviceInfo(
            vendorID: vendorID,
            productID: productID,
            productName: productName
        )
    }

    /// Check if a device is a Magic Mouse
    static func isMagicMouse(_ device: UnsafeMutableRawPointer) -> Bool {
        guard let info = getDeviceInfo(from: device) else {
            return false
        }
        return info.isMagicMouse
    }
}
