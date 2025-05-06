import Foundation

public class LlamaConfig {
    public static let shared = LlamaConfig()
    
    private struct Defaults {
        static var contextSize = Self.determineModelContext() ? 2048 : canUseGPU() ? 2048 : 2048
        static var batchSize = 256
        static var temperature: Float = 1.0
        static var topP: Float = 0.98
        static var minP: Float = 0.02
        static var dryMultiplier: Float = 0.7
        static var dryBase: Float = 1.50
        static var maxTokens = 1024
        static var flashAttention = true
        static var loraScale: Float = 0.7
        static var historyMessageCount = 12
        static var maxParagraphs = 3
        static var minParagraphLength = 100
        static var useMetalGPU = Self.canUseGPU()
        
        static func determineModelContext() -> Bool {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let gigabyte: UInt64 = 1024 * 1024 * 1024
            return physicalMemory > 6 * gigabyte
        }
        
        static func canUseGPU() -> Bool {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let gigabyte: UInt64 = 1024 * 1024 * 1024
            return physicalMemory >= 5 * gigabyte
        }
    }
    
    // MARK: - Properties with UserDefaults Persistence
    var contextSize: Int
    var batchSize: Int
    var temperature: Float
    var dryMultiplier: Float
    var topP: Float
    var minP: Float
    var dryBase: Float
    var maxTokens: Int
    var flashAttention: Bool
    var loraScale: Float
    public var historyMessageCount: Int
    var maxParagraphs: Int
    var minParagraphLength: Int
    var useMetalGPU: Bool
    
    private init() {
        self.contextSize = Defaults.contextSize
        self.batchSize = Defaults.batchSize
        self.temperature = Defaults.temperature
        self.dryMultiplier = Defaults.dryMultiplier
        self.topP = Defaults.topP
        self.minP = Defaults.minP
        self.dryBase = Defaults.dryBase
        self.maxTokens = Defaults.maxTokens
        self.flashAttention = Defaults.flashAttention
        self.loraScale = Defaults.loraScale
        self.historyMessageCount = Defaults.historyMessageCount
        self.maxParagraphs = Defaults.maxParagraphs
        self.minParagraphLength = Defaults.minParagraphLength
        self.useMetalGPU = Defaults.useMetalGPU
    }
    
    public func resetToDefaults() {
        contextSize = Defaults.contextSize
        batchSize = Defaults.batchSize
        temperature = Defaults.temperature
        dryMultiplier = Defaults.dryMultiplier
        topP = Defaults.topP
        minP = Defaults.minP
        dryBase = Defaults.dryBase
        maxTokens = Defaults.maxTokens
        flashAttention = Defaults.flashAttention
        loraScale = Defaults.loraScale
        historyMessageCount = Defaults.historyMessageCount
        maxParagraphs = Defaults.maxParagraphs
        minParagraphLength = Defaults.minParagraphLength
        useMetalGPU = Defaults.useMetalGPU
    }
}
