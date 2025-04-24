import os
class LoggerService {
    static let shared = LoggerService()
    
    private let logger: Logger
    private let loggingQueue = DispatchQueue(label: "com.lowkey.logging", qos: .utility)

    private init() {
        logger = Logger(subsystem: "com.lowkey.milkteacafe", category: "General")
    }
    
    // Direct logging without forced main thread dispatch
    private func logDirectly(_ message: String, level: OSLogType) {
        logger.log(level: level, "\(message, privacy: .public)")
    }
    
    func debug(_ message: String) {
        loggingQueue.async { self.logDirectly("🐛 \(message)", level: .debug) }
    }
    
    func info(_ message: String) {
        loggingQueue.async { self.logDirectly("ℹ️ \(message)", level: .info) }
    }
    
    func warning(_ message: String) {
        loggingQueue.async { self.logDirectly("⚠️ \(message)", level: .error) }
    }
    
    func error(_ message: String) {
        loggingQueue.async { self.logDirectly("❌ \(message)", level: .fault) }
    }
}
