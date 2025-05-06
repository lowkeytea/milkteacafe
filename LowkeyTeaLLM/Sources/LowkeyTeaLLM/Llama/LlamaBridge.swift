import Foundation
import llama
import OSLog

typealias LlamaLoraAdapter = OpaquePointer

/// LlamaBridge is an actor registry that manages LlamaModel weights and LlamaContext instances
/// It maintains backward compatibility by delegating operations to a default context
public actor LlamaBridge {
    // MARK: - Sequence ID Management
    
    /// Sequence ID management to ensure unique IDs for each context 
    private var nextSequenceId: Int32 = 1
    private var assignedSequenceIds = Set<Int32>()
    
    /// Atomically generate a new unique sequence ID
    public func generateUniqueSequenceId() -> Int32 {
        // This runs within the actor so it's automatically synchronized
        let newId = nextSequenceId
        nextSequenceId += 1
        assignedSequenceIds.insert(newId)
        return newId
    }
    
    /// Release a sequence ID when no longer needed
    public func releaseSequenceId(_ id: Int32) {
        assignedSequenceIds.remove(id)
        LoggerService.shared.debug("Released sequence ID: \(id), active IDs: \(assignedSequenceIds.count)")
    }
    
    // MARK: - Weights Management
    
    /// Registry of all loaded model weights
    private var modelWeights: [String: LlamaModel] = [:]
    
    /// Tracks which contexts are using which weights
    private var weightUsage: [String: Set<String>] = [:]
    
    // MARK: - Singleton
    
    // Shared instance - accessible without await
    public static nonisolated let shared = LlamaBridge()
    
    // MARK: - Properties
    
    /// Registry of all loaded contexts
    private var contexts: [String: LlamaContext] = [:]
    
    /// The ID of the current default context
    private var defaultContextId: String?
    
    // MARK: - Initialization
    
    init() {
        // Initialize the llama backend once during the app's lifetime
        llama_backend_init()
        LoggerService.shared.info("LlamaBridge initialized with backend")
    }
    
    // MARK: - Model Weight Management
    
    /// Load model weights from the specified path
    /// - Parameters:
    ///   - modelPath: Path to the model file
    ///   - weightId: Optional unique identifier for these weights, defaults to the filename
    /// - Returns: The LlamaModel instance containing the weights
    public func loadModelWeights(modelPath: String, weightId: String? = nil) async throws -> LlamaModel {
        // Use filename as default weight ID if none provided
        let finalWeightId = weightId ?? URL(fileURLWithPath: modelPath).lastPathComponent
        
        // Check if weights are already loaded
        if let existingWeights = modelWeights[finalWeightId] {
            LoggerService.shared.debug("Using existing weights for \(finalWeightId)")
            return existingWeights
        }
        
        // Load new weights
        do {
            let newWeights = try LlamaModel(id: finalWeightId, path: modelPath)
            modelWeights[finalWeightId] = newWeights
            weightUsage[finalWeightId] = Set<String>()
            
            LoggerService.shared.info("Loaded new model weights for \(finalWeightId) from \(modelPath)")
            return newWeights
        } catch {
            LoggerService.shared.error("Failed to load model weights for \(finalWeightId): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Explicitly unload model weights if they are not in use
    /// - Parameter weightId: ID of the weights to unload
    /// - Returns: True if weights were unloaded, false if they're still in use or don't exist
    public func unloadModelWeights(weightId: String) async -> Bool {
        // Check if weights exist
        guard let weights = modelWeights[weightId] else {
            LoggerService.shared.warning("Cannot unload weights \(weightId): not found")
            return false
        }
        
        // Check if weights are in use
        if let usageSet = weightUsage[weightId], !usageSet.isEmpty {
            let contextList = usageSet.joined(separator: ", ")
            LoggerService.shared.warning("Cannot unload weights \(weightId): still in use by contexts [\(contextList)]")
            return false
        }
        
        // Unload the weights
        LoggerService.shared.info("Unloading model weights \(weightId)")
        await weights.cleanup()
        modelWeights.removeValue(forKey: weightId)
        weightUsage.removeValue(forKey: weightId)
        return true
    }
    
    /// Get a list of all loaded weight IDs
    /// - Returns: Array of weight IDs
    public func getLoadedWeightIds() -> [String] {
        return Array(modelWeights.keys)
    }
    
    // MARK: - Context Management
    
    /// Get a specific context by ID, or create if it doesn't exist
    /// - Parameters:
    ///   - id: Unique identifier for the context
    ///   - path: Optional path to the model file
    /// - Returns: The requested LlamaContext instance (actor-isolated)
    public func getContext(id: String, path: String? = nil) -> LlamaContext {
        if let existingContext = contexts[id] {
            return existingContext
        }
        
        // Get a new sequence ID for this context
        let sequenceId = generateUniqueSequenceId()
        
        // Creating a new LlamaContext is inexpensive as it doesn't actually load the model yet
        let newContext = LlamaContext(id: id, path: path, sequenceId: sequenceId)
        contexts[id] = newContext
        
        // Set as default if it's the first context
        if defaultContextId == nil {
            defaultContextId = id
            LoggerService.shared.info("Set \(id) as default context")
        }
        
        return newContext
    }
    
    /// Create a new context that shares weights with an existing context
    /// - Parameters:
    ///   - id: Unique identifier for the new context
    ///   - weightId: ID of the weights to use
    /// - Returns: The new LlamaContext instance using shared weights
    public func createSharedContext(id: String, weightId: String) async throws -> LlamaContext {
        // Verify weights exist
        guard let weights = modelWeights[weightId] else {
            throw LlamaError.modelNotLoaded
        }
        
        // Get a new sequence ID for this context
        let sequenceId = generateUniqueSequenceId()
        
        // Create new context
        let newContext = LlamaContext(id: id, sequenceId: sequenceId)
        contexts[id] = newContext
        
        // Register this context as using these weights
        weightUsage[weightId, default: Set<String>()].insert(id)
        
        // Return the context - note that it's not fully initialized yet,
        // the caller needs to call context.initializeWithSharedWeights(...)
        return newContext
    }
    
    /// Get the current default context
    /// - Returns: The default LlamaContext or nil if none exists
    public func getDefaultContext() -> LlamaContext? {
        guard let defaultId = defaultContextId, let context = contexts[defaultId] else {
            return nil
        }
        
        return context
    }
    
    /// Set a specific context as the default
    /// - Parameter id: The ID of the context to set as default
    /// - Returns: True if successful, false if the context doesn't exist
    public func setDefaultContext(id: String) -> Bool {
        guard contexts[id] != nil else {
            LoggerService.shared.warning("Attempted to set non-existent context \(id) as default")
            return false
        }
        
        defaultContextId = id
        LoggerService.shared.info("Changed default context to \(id)")
        return true
    }
    
    /// Unload a specific context
    /// - Parameter id: The ID of the context to unload
    public func unloadContext(id: String) async {
        let contextToUnload = contexts[id]
        let isDefault = id == defaultContextId
        
        // If we're unloading the default, find a new default
        if isDefault {
            defaultContextId = contexts.keys.first(where: { $0 != id })
            if let newDefault = defaultContextId {
                LoggerService.shared.info("Default context changed to \(newDefault) after unloading \(id)")
            } else {
                LoggerService.shared.info("No default context after unloading \(id)")
            }
        }
        
        // Remove context from weight usage tracking
        for (weightId, contextIds) in weightUsage {
            if contextIds.contains(id) {
                weightUsage[weightId]?.remove(id)
                LoggerService.shared.debug("Removed context \(id) from weight usage tracking for \(weightId)")
            }
        }
        
        // Perform actual unloading
        if let context = contextToUnload {
            LoggerService.shared.info("Unloading context \(id)")
            await context.cleanupContextOnly() // Only clean up the context, not the weights
            contexts.removeValue(forKey: id)
        }
    }
    
    /// Get a list of all loaded context IDs
    /// - Returns: Array of context IDs
    public func getLoadedContextIds() -> [String] {
        return Array(contexts.keys)
    }
    
    /// Check if a specific context is loaded
    /// - Parameter id: The ID of the context to check
    /// - Returns: True if the context is loaded and initialized
    public func isContextLoaded(id: String) async -> Bool {
        guard let context = contexts[id] else { return false }
        return await context.isLoaded()
    }
    
    // MARK: - Backward Compatibility Methods
    
    /// Backward compatibility for getModel - now redirects to getContext
    @available(*, deprecated, message: "Use getContext instead")
    public func getModel(id: String, path: String? = nil) -> LlamaContext {
        return getContext(id: id, path: path)
    }
    
    /// Backward compatibility for getDefaultModel - now redirects to getDefaultContext
    @available(*, deprecated, message: "Use getDefaultContext instead")
    public func getDefaultModel() -> LlamaContext? {
        return getDefaultContext()
    }
    
    /// Check if the model has been restarted - for backward compatibility
    public func isRestarted() async -> Bool {
        if let context = getDefaultContext() {
            return await context.restarted
        }
        return true
    }
    
    /// Check if any model is loaded (for backward compatibility)
    public func isLoaded() async -> Bool {
        guard let context = getDefaultContext() else { return false }
        return await context.isLoaded()
    }
    
    /// Load a model from the specified path (backward compatibility)
    /// - Parameters:
    ///   - modelPath: Path to the model file
    ///   - formatter: Optional prompt formatter
    /// - Returns: True if the model was loaded successfully
    public func loadModel(modelPath: String, formatter: PromptFormatter? = nil) async -> Bool {
        // Generate a model ID from the path
        let modelId = URL(fileURLWithPath: modelPath).lastPathComponent
        
        // First load the weights
        do {
            _ = try await loadModelWeights(modelPath: modelPath, weightId: modelId)
        } catch {
            LoggerService.shared.error("Failed to load model weights: \(error.localizedDescription)")
            return false
        }
        
        // Get or create the context
        let context = getContext(id: modelId, path: modelPath)
        
        // Initialize the context with the weights
        let success = await context.loadModel(modelPath: modelPath, formatter: formatter)
        
        // Register weight usage
        if success {
            weightUsage[modelId, default: Set<String>()].insert(modelId)
            _ = setDefaultContext(id: modelId)
        }
        
        return success
    }
    
    /// A synchronous wrapper for loadModel that can be called without await
    /// Returns immediately but performs loading asynchronously
    public nonisolated func loadModelAndNotify(modelPath: String, formatter: PromptFormatter? = nil) {
        Task {
            let success = await loadModel(modelPath: modelPath, formatter: formatter)
            
            if !success {
                LoggerService.shared.error("Failed to load model at \(modelPath)")
            }
        }
    }
    
    /// Switch the current agent (backward compatibility)
    public func switchAgent(_ newAgent: String) async throws {
        guard let defaultContext = getDefaultContext() else {
            throw LlamaError.modelNotLoaded
        }
        
        try await defaultContext.switchAgent(newAgent)
    }
    
    // MARK: - Methods Delegated to Default Context
    
    /// Set cancellation state on the default context
    func setCancelled(_ value: Bool) async {
        if let context = getDefaultContext() {
            await context.setCancelled(value)
        }
    }
    
    /// Check if generation should continue
    public func shouldContinueGeneration() async -> Bool {
        guard let context = getDefaultContext() else { return false }
        return await context.shouldContinueGeneration()
    }
    
    /// Complete the next token in generation - properly handles actor isolation
    public func completionLoop(maxTokens: Int, currentToken: inout Int) async -> String? {
        guard let context = getDefaultContext() else { return nil }
        return await context.completionLoop(maxTokens: maxTokens, currentToken: &currentToken)
    }
    
    /// Append a user message for processing - properly handles actor isolation
    public func appendUserMessage(userMessage: String) async {
        if let context = getDefaultContext() {
            await context.appendUserMessage(userMessage: userMessage)
        }
    }
    
    /// Initialize completion with the given text - properly handles actor isolation
    public  func completionInit(_ text: String, setLogits: Bool = true) async -> Bool {
        return await getDefaultContext()?.completionInit(text, setLogits: setLogits) ?? false
    }
    
    /// Clear the context and optionally the KV cache
    public func clearContext(clearKvCache: Bool = true) async {
        if let context = getDefaultContext() {
            await context.clearContext(clearKvCache: clearKvCache)
        }
    }
    
    /// Check if a context reset is pending
    public func checkResetPending() async -> Bool {
        guard let context = getDefaultContext() else { return false }
        return await context.checkResetPending()
    }
    
    // MARK: - Cleanup
    
    /// Unload all contexts and clean up
    public func unloadAllContexts() async {
        let contextIds = getLoadedContextIds()
        for id in contextIds {
            await unloadContext(id: id)
        }
    }
    
    /// Unload all contexts and weights
    public func unloadAll() async {
        // First unload all contexts
        await unloadAllContexts()
        
        // Then unload all weights
        let weightIds = getLoadedWeightIds()
        for id in weightIds {
            // At this point all contexts should be unloaded, so this should succeed
            let success = await unloadModelWeights(weightId: id)
            if !success {
                LoggerService.shared.warning("Failed to unload weights \(id)")
            }
        }
    }
    
    /// Unload all models - backward compatibility
    @available(*, deprecated, message: "Use unloadAllContexts or unloadAll instead")
    public func unloadAllModels() async {
        await unloadAllContexts()
    }
    
    /// Clean up the default model (backward compatibility)
    public func cleanup() async {
        guard let defaultContext = getDefaultContext() else {
            return
        }
        
        await defaultContext.cleanupContextOnly()
    }
    
    /// Clear the KV cache for the default context (backward compatibility)
    public func clearKVCache() async {
        if let context = getDefaultContext() {
            await context.clearKVCache()
        }
    }
    
    // Create a static cleanup method that doesn't capture self
    private static func performCleanup() {
        // Clean up the llama backend
        llama_backend_free()
        LoggerService.shared.info("LlamaBridge backend cleanup completed")
    }
    
    deinit {
        // Log deallocation
        LoggerService.shared.info("LlamaBridge deallocating")
        
        // Perform backend cleanup
        Self.performCleanup()
    }
    
    // MARK: - Weight Usage Statistics
    
    /// Get information about which weights are being used by which contexts
    /// - Returns: Dictionary mapping weight IDs to sets of context IDs
    func getWeightUsageMap() -> [String: Set<String>] {
        return weightUsage
    }
    
    /// Get stats about shared model usage
    /// - Returns: Tuple containing count of shared contexts, total memory savings
    func getSharedModelStats() async -> (contextCount: Int, weightCount: Int, memorySavings: String) {
        // Count unique weight instances
        let uniqueWeightCount = modelWeights.count
        
        // Count contexts
        let contextCount = contexts.count
        
        // Each shared weight saves approximately its file size in memory
        // For a rough estimate, assume each model is about 4GB
        let savedMemoryGB = max(0, (contextCount - uniqueWeightCount) * 4)
        
        return (
            contextCount: contextCount,
            weightCount: uniqueWeightCount,
            memorySavings: savedMemoryGB > 0 ? "~\(savedMemoryGB) GB" : "0 GB"
        )
    }
    
    // MARK: - Legacy Shared Weights Methods
    
    /// Get or create weights for a model path (legacy method, use loadModelWeights instead)
    /// - Parameters:
    ///   - modelPath: Path to the model file
    ///   - key: Unique key for these weights
    /// - Returns: A shared model instance
    @available(*, deprecated, message: "Use loadModelWeights instead")
    func getOrCreateWeights(for modelPath: String, key: String) async throws -> LlamaModel {
        let compositeKey = "\(modelPath)-\(key)"
        
        // Check if weights already exist
        if let existingModel = modelWeights[compositeKey] {
            LoggerService.shared.debug("Using existing model for \(modelPath)")
            weightUsage[compositeKey, default: Set<String>()].insert(key)
            return existingModel
        }
        
        // Create new model weights
        do {
            let newModel = try LlamaModel(id: compositeKey, path: modelPath)
            modelWeights[compositeKey] = newModel
            weightUsage[compositeKey] = [key]
            LoggerService.shared.info("Created new model for \(modelPath) with id \(compositeKey)")
            
            return newModel
        } catch {
            LoggerService.shared.error("Failed to create model for \(modelPath): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Release weights (legacy method, use unloadModelWeights instead)
    /// - Parameter model: The model to release
    @available(*, deprecated, message: "Use unloadModelWeights instead")
    func releaseWeights(_ model: LlamaModel) async {
        // Find the weight ID
        guard let weightId = modelWeights.first(where: { $0.value === model })?.key else {
            LoggerService.shared.warning("Attempted to release unknown weights")
            return
        }
        
        // Remove the context's usage of these weights
        if var usageSet = weightUsage[weightId] {
            // Just remove one usage - doesn't matter which one since we're using reference counting
            if let firstUsage = usageSet.first {
                usageSet.remove(firstUsage)
                weightUsage[weightId] = usageSet
            }
            
            // If no more usages, unload the weights
            if usageSet.isEmpty {
                _ = await unloadModelWeights(weightId: weightId)
            }
        }
    }
    
    /// Clean up all weights (legacy method, use unloadAll instead)
    @available(*, deprecated, message: "Use unloadAll instead")
    func cleanupAllWeights() async {
        await unloadAll()
    }
}

// MARK: - ModelState Enum

public enum ModelState: Equatable {
    case unloaded
    case loading
    case loaded
    case error(Error)
    
    public static func == (lhs: ModelState, rhs: ModelState) -> Bool {
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
