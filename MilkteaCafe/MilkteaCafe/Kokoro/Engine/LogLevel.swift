import Foundation
import os

/// Log levels similar to Android's Log.* levels
public enum LogLevel: Int {
    case verbose = 2
    case debug   = 3
    case info    = 4
    case warn    = 5
    case error   = 6
}

/// A logger that logs messages with a tag and level, using os.log under the hood.
public class KokoroLogger {
    private let tag: String
    private let subsystem: String
    private let osLog: OSLog

    /// Global minimum log level; messages below this level will be ignored.
    public static var minimumLogLevel: LogLevel = .debug

    // MARK: - Factory Methods

    /// Creates a logger instance tagged with the class name of T
    public static func create<T>(for type: T.Type = T.self) -> KokoroLogger {
        let tag = String(describing: type)
        return KokoroLogger(tag: tag)
    }

    /// Fallback logger creation without type inference
    public static func create(tag: String) -> KokoroLogger {
        return KokoroLogger(tag: tag)
    }

    // MARK: - Initialization
    private init(tag: String) {
        self.tag = tag
        self.subsystem = Bundle.main.bundleIdentifier ?? "Kokoro"
        self.osLog = OSLog(subsystem: subsystem, category: tag)
    }

    // MARK: - Logging APIs
    public func v(_ message: String) {
        log(level: .verbose, message: message)
    }

    public func d(_ message: String) {
        log(level: .debug, message: message)
    }

    public func i(_ message: String) {
        log(level: .info, message: message)
    }

    public func w(_ message: String) {
        log(level: .warn, message: message)
    }

    public func e(_ message: String) {
        log(level: .error, message: message)
    }

    public func w(_ message: String, error: Error) {
        log(level: .warn, message: "\(message) - Error: \(error)")
    }

    public func e(_ message: String, error: Error) {
        log(level: .error, message: "\(message) - Error: \(error)")
    }

    // MARK: - Internal
    private func log(level: LogLevel, message: String) {
        guard level.rawValue >= KokoroLogger.minimumLogLevel.rawValue else { return }
        let osType: OSLogType
        switch level {
            case .verbose: osType = .debug
            case .debug:   osType = .debug
            case .info:    osType = .info
            case .warn:    osType = .default
            case .error:   osType = .error
        }
        os_log("%{public}@", log: osLog, type: osType, "[\(tag)] \(message)")
    }
} 
