import Foundation
import llama
import OSLog

typealias LlamaLoraAdapter = OpaquePointer

/// LlamaBridge is a registry that manages multiple LlamaModel instances
/// It maintains backward compatibility by delegating operations to a default model
actor LlamaBridge {
    // MARK: - Shared Weights Management
    
    /// Registry of all loaded model weights
    private var weightsByPath: [String: LlamaWeights] = [:]
    // MARK: - Singleton
    
    static let shared = LlamaBridge()
    
    // MARK: - Properties
    
    /// Registry of all loaded models
    private var models: [String: LlamaModel] = [:]
    
    /// The ID of the current default model
    private var defaultModelId: String?
    
    // MARK: - Initialization
    
    init() {
        // Initialize the llama backend once during the app's lifetime
        llama_backend_init()
        LoggerService.shared.info("LlamaBridge initialized with backend")
    }
    
    // MARK: - Model Registry Methods
    
    /// Get a specific model by ID, or create if it doesn't exist
    /// - Parameters:
    ///   - id: Unique identifier for the model
    ///   - path: Optional path to the model file
    /// - Returns: The requested LlamaModel instance
    func getModel(id: String, path: String? = nil) -> LlamaModel {
        if let existingModel = models[id] {
            return existingModel
        }
        
        let newModel = LlamaModel(id: id, path: path)
        models[id] = newModel
        
        // Set as default if it's the first model
        if defaultModelId == nil {
            defaultModelId = id
            LoggerService.shared.info("Set \(id) as default model")
        }
        
        return newModel
    }
    
    /// Get the current default model
    /// - Returns: The default LlamaModel or nil if none exists
    func getDefaultModel() -> LlamaModel? {
        guard let defaultId = defaultModelId, let model = models[defaultId] else {
            return nil
        }
        
        return model
    }
    
    /// Set a specific model as the default
    /// - Parameter id: The ID of the model to set as default
    /// - Returns: True if successful, false if the model doesn't exist
    func setDefaultModel(id: String) -> Bool {
        guard models[id] != nil else {
            LoggerService.shared.warning("Attempted to set non-existent model \(id) as default")
            return false
        }
        
        defaultModelId = id
        LoggerService.shared.info("Changed default model to \(id)")
        return true
    }
    
    /// Unload a specific model
    /// - Parameter id: The ID of the model to unload
    func unloadModel(id: String) async {
        let modelToUnload = models[id]
        let isDefault = id == defaultModelId
        
        // If we're unloading the default, find a new default
        if isDefault {
            defaultModelId = models.keys.first(where: { $0 != id })
            if let newDefault = defaultModelId {
                LoggerService.shared.info("Default model changed to \(newDefault) after unloading \(id)")
            } else {
                LoggerService.shared.info("No default model after unloading \(id)")
            }
        }
        
        // Perform actual unloading
        if let model = modelToUnload {
            LoggerService.shared.info("Unloading model \(id)")
            await model.cleanup()
            models.removeValue(forKey: id)
        }
    }
    
    /// Check if the model has been restarted - for backward compatibility
    func isRestarted() -> Bool {
        return getDefaultModel()?.restarted ?? true
    }
    
    /// Get a list of all loaded model IDs
    /// - Returns: Array of model IDs
    func getLoadedModelIds() -> [String] {
        return Array(models.keys)
    }
    
    /// Check if a specific model is loaded
    /// - Parameter id: The ID of the model to check
    /// - Returns: True if the model is loaded and initialized
    func isModelLoaded(id: String) -> Bool {
        return models[id]?.isLoaded() ?? false
    }
    
    // MARK: - Backward Compatibility Methods
    
    /// Check if any model is loaded (for backward compatibility)
    func isLoaded() -> Bool {
        return getDefaultModel()?.isLoaded() ?? false
    }
    
    /// Load a model from the specified path (backward compatibility)
    /// - Parameters:
    ///   - modelPath: Path to the model file
    ///   - formatter: Optional prompt formatter
    /// - Returns: True if the model was loaded successfully
    func loadModel(modelPath: String, formatter: PromptFormatter? = nil) async -> Bool {
        // Generate a model ID from the path
        let modelId = URL(fileURLWithPath: modelPath).lastPathComponent
        
        // Get or create the model
        let model = getModel(id: modelId, path: modelPath)
        
        // Load it (using await now)
        let success = await model.loadModel(modelPath: modelPath, formatter: formatter)
        
        // Set as default if successful
        if success {
            setDefaultModel(id: modelId)
        }
        
        return success
    }
    
    /// Switch the current agent (backward compatibility)
    func switchAgent(_ newAgent: String) async throws {
        guard let defaultModel = getDefaultModel() else {
            throw LlamaError.modelNotLoaded
        }
        
        try await defaultModel.switchAgent(newAgent)
    }
    
    // MARK: - Methods Delegated to Default Model
    
    /// Set cancellation state on the default model
    func setCancelled(_ value: Bool) {
        getDefaultModel()?.setCancelled(value)
    }
    
    /// Check if generation should continue
    func shouldContinueGeneration() -> Bool {
        return getDefaultModel()?.shouldContinueGeneration() ?? false
    }
    
    /// Complete the next token in generation
    func completionLoop(maxTokens: Int, currentToken: inout Int) -> String? {
        return getDefaultModel()?.completionLoop(maxTokens: maxTokens, currentToken: &currentToken)
    }
    
    /// Append a user message for processing
    func appendUserMessage(userMessage: String) {
        getDefaultModel()?.appendUserMessage(userMessage: userMessage)
    }
    
    /// Initialize completion with the given text
    func completionInit(_ text: String, setLogits: Bool = true) async -> Bool {
        return await getDefaultModel()?.completionInit(text, setLogits: setLogits) ?? false
    }
    
    /// Clear the context and optionally the KV cache
    func clearContext(clearKvCache: Bool = true) {
        getDefaultModel()?.clearContext(clearKvCache: clearKvCache)
    }
    
    /// Check if a context reset is pending
    func checkResetPending() -> Bool {
        return getDefaultModel()?.checkResetPending() ?? false
    }
    
    // MARK: - Cleanup
    
    /// Unload all models and clean up
    func unloadAllModels() async {
        let modelIds = getLoadedModelIds()
        for id in modelIds {
            await unloadModel(id: id)
        }
    }
    
    /// Clean up the default model (backward compatibility)
    func cleanup() async {
        guard let defaultModel = getDefaultModel() else {
            return
        }
        
        await defaultModel.cleanup()
    }
    
    /// Clear the KV cache for the default model (backward compatibility)
    func clearKVCache() {
        getDefaultModel()?.clearKVCache()
    }
    
    deinit {
        // Clean up shared weights first
        cleanupAllWeights()
        
        // Clean up the llama backend
        llama_backend_free()
        LoggerService.shared.info("LlamaBridge deallocated with backend cleanup")
    }
    
    // MARK: - Shared Weights Methods
    
    /// Get or create weights for a model path
    /// - Parameter path: Path to the model file
    /// - Returns: A shared weights instance
    func getOrCreateWeights(for path: String) throws -> LlamaWeights {
        // Check if we already have weights for this path
        if let existingWeights = weightsByPath[path] {
            LoggerService.shared.debug("Using existing weights for \(path)")
            existingWeights.retain()
            return existingWeights
        }
        
        // Create new weights
        let id = URL(fileURLWithPath: path).lastPathComponent
        let newWeights = try LlamaWeights(id: id, path: path)
        newWeights.retain() // Initial retain
        weightsByPath[path] = newWeights
        LoggerService.shared.info("Created new weights for \(path) with id \(id)")
        
        return newWeights
    }
    
    /// Release weights for a path
    /// - Parameter weights: The weights to release
    func releaseWeights(_ weights: LlamaWeights) {
        weights.release()
        // If reference count reaches zero, it will be cleaned up in LlamaWeights.release()
        // We can remove from our registry
        for (path, w) in weightsByPath where w.id == weights.id {
            if w.refCount <= 0 {
                weightsByPath.removeValue(forKey: path)
                break
            }
        }
    }
    
    /// Clean up all weights
    func cleanupAllWeights() {
        for (_, weights) in weightsByPath {
            LoggerService.shared.debug("Releasing all references to weights \(weights.id)")
            weights.release()
        }
        weightsByPath.removeAll()
    }
    
    /// Get stats about shared model usage
    /// - Returns: Tuple containing count of shared models, total memory savings
    func getSharedModelStats() -> (count: Int, memorySavings: String) {
        // Get unique model paths being shared
        let uniquePaths = Set(weightsByPath.keys)
        
        // Get count of models using shared weights
        let totalModelsUsingSharedWeights = models.values.count
        
        // Each shared model saves approximately its file size in memory
        // For a rough estimate, assume each model is about 4GB
        let savedMemoryGB = max(0, (totalModelsUsingSharedWeights - uniquePaths.count) * 4)
        
        return (
            count: totalModelsUsingSharedWeights,
            memorySavings: savedMemoryGB > 0 ? "~\(savedMemoryGB) GB" : "0 GB"
        )
    }
}

// MARK: - ModelState Enum

enum ModelState: Equatable {
    case unloaded
    case loading
    case loaded
    case error(Error)
    
    static func == (lhs: ModelState, rhs: ModelState) -> Bool {
        switch (lhs, rhs) {
        case (.unloaded, .unloaded),
             (.loading, .loading),
             (.loaded, .loaded):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Notification Name Extensions

extension Notification.Name {
    static let modelStateChanged = Notification.Name("modelStateChanged")
    static let modelUnloaded = Notification.Name("modelUnloaded")
    static let modelLoading = Notification.Name("modelLoading")
    static let modelLoaded = Notification.Name("modelLoaded")
    static let modelLoadFailed = Notification.Name("modelLoadFailed")
}
