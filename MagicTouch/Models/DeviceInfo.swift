//
//  DeviceInfo.swift
//  MagicTouch
//
//  Device information structure
//

import Foundation

struct DeviceInfo {
    let vendorID: Int
    let productID: Int
    let productName: String?

    var isMagicMouse: Bool {
        // Apple Vendor IDs:
        // - 0x05AC (1452): USB devices (USB_VENDOR_ID_APPLE)
        // - 0x004C (76): Bluetooth devices (BT_VENDOR_ID_APPLE)
        guard vendorID == 0x05AC || vendorID == 0x004C else { return false }

        // Magic Mouse Product IDs (from Linux kernel hid-ids.h):
        // - 0x030D (781): Magic Mouse 1
        // - 0x0269 (617): Magic Mouse 2 (Lightning)
        // - 0x0323 (803): Magic Mouse 2 USB-C (2024)
        return productID == 0x030D || productID == 0x0269 || productID == 0x0323
    }

    var modelName: String {
        switch productID {
        case 0x030D: return "Magic Mouse"
        case 0x0269: return "Magic Mouse 2"
        case 0x0323: return "Magic Mouse 2 USB-C"
        default: return productName ?? "Magic Mouse"
        }
    }

    var connectionType: String {
        vendorID == 0x004C ? "Bluetooth" : "USB"
    }
}
