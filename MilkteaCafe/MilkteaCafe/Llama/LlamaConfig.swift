import Foundation

class LlamaConfig: ObservableObject {
    static let shared = LlamaConfig()
    
    private struct Defaults {
        static let contextSize = Self.determineModelContext() ? 2560 : canUseGPU() ? 2048 : 1536
        static let batchSize = 256
        static let temperature: Float = 1.0
        static let topP: Float = 0.98
        static let minP: Float = 0.02
        static let dryMultiplier: Float = 0.7
        static let dryBase: Float = 1.50
        static let maxTokens = 256
        static let flashAttention = true
        static let loraScale: Float = 0.7
        static let historyMessageCount = Self.determineModelContext() ? 5 : canUseGPU() ? 4 : 3
        static let maxParagraphs = 3
        static let minParagraphLength = 100
        static let useMetalGPU = Self.canUseGPU()
        
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
    
    // MARK: - Published Properties with UserDefaults Persistence
    @Published var contextSize: Int {
        didSet {
            UserDefaults.standard.set(contextSize, forKey: "contextSize")
            notifyConfigChanged()
        }
    }
    
    @Published var batchSize: Int {
        didSet {
            UserDefaults.standard.set(batchSize, forKey: "batchSize")
            notifyConfigChanged()
        }
    }
    
    @Published var temperature: Float {
        didSet {
            UserDefaults.standard.set(temperature, forKey: "temperature")
            notifyConfigChanged()
        }
    }
    
    @Published var dryMultiplier: Float {
        didSet {
            UserDefaults.standard.set(dryMultiplier, forKey: "dryMultiplier")
            notifyConfigChanged()
        }
    }
    
    @Published var topP: Float {
        didSet {
            UserDefaults.standard.set(topP, forKey: "topP")
            notifyConfigChanged()
        }
    }
    
    @Published var minP: Float {
        didSet {
            UserDefaults.standard.set(minP, forKey: "minP")
            notifyConfigChanged()
        }
    }
    
    @Published var dryBase: Float {
        didSet {
            UserDefaults.standard.set(dryBase, forKey: "dryBase")
            notifyConfigChanged()
        }
    }
    
    @Published var maxTokens: Int {
        didSet {
            UserDefaults.standard.set(maxTokens, forKey: "maxTokens")
            notifyConfigChanged()
        }
    }
    
    @Published var flashAttention: Bool {
        didSet {
            UserDefaults.standard.set(flashAttention, forKey: "flashAttention")
            notifyConfigChanged()
        }
    }
    
    @Published var loraScale: Float {
        didSet {
            UserDefaults.standard.set(loraScale, forKey: "loraScale")
            notifyConfigChanged()
        }
    }
    
    @Published var historyMessageCount: Int {
        didSet {
            UserDefaults.standard.set(historyMessageCount, forKey: "historyMessageCount")
            notifyConfigChanged()
        }
    }
    
    @Published var maxParagraphs: Int {
        didSet {
            UserDefaults.standard.set(maxParagraphs, forKey: "maxParagraphs")
            notifyConfigChanged()
        }
    }
    
    @Published var minParagraphLength: Int {
        didSet {
            UserDefaults.standard.set(minParagraphLength, forKey: "minParagraphLength")
            notifyConfigChanged()
        }
    }
    
    @Published var useMetalGPU: Bool {
        didSet {
            // Only allow setting to true if device can support GPU
            if useMetalGPU {
                UserDefaults.standard.set(useMetalGPU, forKey: "useMetalGPU")
                notifyConfigChanged()
            } else {
                UserDefaults.standard.set(false, forKey: "useMetalGPU")
            }
        }
    }
    
    private init() {
        let defaults = UserDefaults.standard
        
        func getValue<T>(_ key: String, defaultValue: T) -> T {
            return defaults.object(forKey: key) as? T ?? defaultValue
        }
        
        self.contextSize = getValue("contextSize", defaultValue: Defaults.contextSize)
        self.batchSize = getValue("batchSize", defaultValue: Defaults.batchSize)
        self.temperature = getValue("temperature", defaultValue: Defaults.temperature)
        self.dryMultiplier = getValue("dryMultiplier", defaultValue: Defaults.dryMultiplier)
        self.topP = getValue("topP", defaultValue: Defaults.topP)
        self.minP = getValue("minP", defaultValue: Defaults.minP)
        self.dryBase = getValue("dryBase", defaultValue: Defaults.dryBase)
        self.maxTokens = getValue("maxTokens", defaultValue: Defaults.maxTokens)
        self.flashAttention = getValue("flashAttention", defaultValue: Defaults.flashAttention)
        self.loraScale = getValue("loraScale", defaultValue: Defaults.loraScale)
        self.historyMessageCount = getValue("historyMessageCount", defaultValue: Defaults.historyMessageCount)
        self.maxParagraphs = getValue("maxParagraphs", defaultValue: Defaults.maxParagraphs)
        self.minParagraphLength = getValue("minParagraphLength", defaultValue: Defaults.minParagraphLength)
        
        self.useMetalGPU = defaults.value(forKey: "useMetalGPU") as? Bool ?? Defaults.useMetalGPU
    }
    
    func resetToDefaults() {
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
        
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        notifyConfigChanged()
    }
    
    private func notifyConfigChanged() {
        NotificationCenter.default.post(name: .llamaConfigChanged, object: self)
    }
}

extension Notification.Name {
    static let llamaConfigChanged = Notification.Name("llamaConfigChanged")
}
