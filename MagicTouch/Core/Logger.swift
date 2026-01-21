//
//  Logger.swift
//  MagicTouch
//
//  Unified logging utility
//

import Foundation
import os.log

enum Logger {

    // MARK: - Log Categories

    private static let subsystem = Bundle.main.bundleIdentifier ?? "MagicTouch"

    static let touch = OSLog(subsystem: subsystem, category: "Touch")
    static let device = OSLog(subsystem: subsystem, category: "Device")
    static let click = OSLog(subsystem: subsystem, category: "Click")
    static let settings = OSLog(subsystem: subsystem, category: "Settings")
    static let general = OSLog(subsystem: subsystem, category: "General")

    // MARK: - Logging Methods

    /// Log a message with specified category and type
    static func log(_ message: String, category: OSLog = general, type: OSLogType = .default) {
        os_log("%{public}@", log: category, type: type, message)
    }

    /// Log an info message
    static func info(_ message: String, category: OSLog = general) {
        os_log("%{public}@", log: category, type: .info, message)
    }

    /// Log a debug message (only in debug builds)
    static func debug(_ message: String, category: OSLog = general) {
        #if DEBUG
        os_log("%{public}@", log: category, type: .debug, message)
        #endif
    }

    /// Log an error message
    static func error(_ message: String, category: OSLog = general) {
        os_log("%{public}@", log: category, type: .error, message)
    }

    /// Log a fault message (critical errors)
    static func fault(_ message: String, category: OSLog = general) {
        os_log("%{public}@", log: category, type: .fault, message)
    }
}
