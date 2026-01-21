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
        // Apple Vendor ID = 0x05AC (1452)
        guard vendorID == 0x05AC else { return false }

        // Magic Mouse 1: 0x030D (781)
        // Magic Mouse 2: 0x0269 (617)
        return productID == 0x030D || productID == 0x0269
    }
}
