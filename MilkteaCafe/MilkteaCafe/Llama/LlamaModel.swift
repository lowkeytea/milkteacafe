import Foundation
import llama
import Combine
import OSLog

/// A class representing an individual llama model instance
/// Handles loading, unloading, and using a specific model
class LlamaModel {
    // MARK: - Properties
    
    /// Unique identifier for this model instance
    let id: String
    
    /// Path to the model file once loaded
    private(set) var currentModelPath: String?
    
    /// Current state of the model
    @Published private(set) var state: ModelState = .unloaded
    
    /// Publisher for state changes
    var statePublisher: AnyPublisher<ModelState, Never> {
        return $state.eraseToAnyPublisher()
    }
    
    /// Llama model pointer
    private var model: OpaquePointer?
    
    /// Shared model weights
    private var sharedWeights: LlamaWeights?
    
    /// Llama context pointer
    private var context: OpaquePointer?
    
    /// Sampler for token generation
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    
    /// List of tokens generated or processed
    private var tokens_list: [llama_token] = []
    
    /// Buffer for temporary character data
    private var temporary_invalid_cchars: [CChar] = []
    
    /// Buffer for tokens
    private let tokenBuffer: UnsafeMutableBufferPointer<llama_token>
    
    /// Maximum number of tokens to process
    private var maxTokens = 4096
    
    /// Current position in the context
    var n_cur: Int32 = 0
    
    /// Effective position in the context
    var effectivePos: Int32 = 0
    
    /// Formatter for prompts
    private var promptFormatter: PromptFormatter?
    
    /// Vocabulary for the model
    private var vocab: OpaquePointer?
    
    /// Map of loaded LoRA adapters
    private var loraAdapters: [String: LlamaLoraAdapter?] = [:]
    
    /// Whether to load LoRA adapters
    var shouldLoadLora: Bool = true
    
    /// Whether generation has been cancelled
    private var isCancelled = false
    
    /// Lock for thread-safe access to cancellation state
    private let cancellationLock = NSLock()
    
    /// Persistent batch for token processing
    private var persistentBatch: UnsafeMutablePointer<llama_batch>?
    
    /// Batch capacity
    private var batchCapacity: Int32
    
    /// Whether the model has been restarted
    var restarted = true
    
    // MARK: - Initialization
    
    init(id: String, path: String? = nil) {
        self.id = id
        self.currentModelPath = path
        self.batchCapacity = Int32(LlamaConfig.shared.contextSize)
        
        // Pre-allocate buffers
        tokenBuffer = UnsafeMutableBufferPointer.allocate(capacity: maxTokens)
        
        // Log initialization
        LoggerService.shared.info("LlamaModel \(id) initialized")
    }
    
    // MARK: - State Management
    
    /// Update the model state and post notifications
    private func updateState(_ newState: ModelState) {
        let oldState = state
        
        // Update state on main thread
        DispatchQueue.main.async {
            self.state = newState
            
            // Post notification on main thread
            let userInfo: [String: Any] = [
                "modelId": self.id,
                "oldState": oldState,
                "newState": newState
            ]
            
            // Post specific state notification
            switch newState {
            case .unloaded:
                NotificationCenter.default.post(
                    name: .modelUnloaded,
                    object: nil,
                    userInfo: userInfo
                )
            case .loading:
                NotificationCenter.default.post(
                    name: .modelLoading,
                    object: nil,
                    userInfo: userInfo
                )
            case .loaded:
                NotificationCenter.default.post(
                    name: .modelLoaded,
                    object: nil,
                    userInfo: userInfo
                )
            case .error(let error):
                var errorInfo = userInfo
                errorInfo["error"] = error
                NotificationCenter.default.post(
                    name: .modelLoadFailed,
                    object: nil,
                    userInfo: errorInfo
                )
            }
            
            // Also post generic state change notification
            NotificationCenter.default.post(
                name: .modelStateChanged,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    // MARK: - Public API
    
    /// Check if the model is loaded and initialized
    func isLoaded() -> Bool {
        return vocab != nil && context != nil && model != nil
    }
    
    /// Set the cancellation flag
    func setCancelled(_ value: Bool) {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        isCancelled = value
    }
    
    /// Check if generation should continue
    func shouldContinueGeneration() -> Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        return !isCancelled
    }
    
    /// Switch to a different agent (LoRA adapter)
    func switchAgent(_ newAgent: String) async throws {
        LoggerService.shared.debug("Switching agent to: \(newAgent)")
        
        // Set cancelled flag
        setCancelled(true)
        
        // Perform synchronous operations on operation queue
        clearContext(clearKvCache: true)
        
        // Ensure a brief delay to let system resources stabilize
        try await Task.sleep(nanoseconds: 300_000_000)
        
        // Load LoRA for the new agent
        await loadLoraForAgent(from: newAgent)
        
        // Re-enable generation
        setCancelled(false)
        
        LoggerService.shared.debug("Agent switch completed successfully")
    }
    
    /// Load a model from the specified path
    func loadModel(modelPath: String, formatter: PromptFormatter? = nil) async -> Bool {
        // Set cancellation flag
        setCancelled(false)
        
        // Update state
        updateState(.loading)
        
        if let formatter = formatter {
            self.promptFormatter = formatter
        }
        
        if isLoaded() {
            cleanupInternal()
        }
        
        do {
            // Get or create shared weights (using await because it's actor-isolated)
            sharedWeights = try await LlamaBridge.shared.getOrCreateWeights(for: modelPath)
            
            // Use the model and vocab from shared weights
            model = sharedWeights?.model
            vocab = sharedWeights?.vocab
            
            // Create our own context with the shared model
            createContext(model: model!, path: modelPath)
            updateSampler()
            
            currentModelPath = modelPath
            updateState(.loaded)
            return true
        } catch {
            LoggerService.shared.error("Failed to load shared model: \(error.localizedDescription)")
            updateState(.error(error))
            return false
        }
    }
    
    /// Initialize completion with the given text
    func completionInit(_ text: String, setLogits: Bool = true) async -> Bool {
        clearBuffers()
        tokens_list = tokenize(text: text, add_bos: false)

        if tokens_list.isEmpty {
            LoggerService.shared.debug("Tokenization resulted in zero tokens")
            return false
        }

        resetPersistentBatch()

        guard let batch = persistentBatch else {
            LoggerService.shared.error("Persistent batch not initialized")
            return false
        }

        for token in tokens_list {
            if batch.pointee.n_tokens >= batchCapacity {
                LoggerService.shared.error("Batch exceeded capacity in completionInit")
                return false
            }
            llama_batch_add(batch: batch, token: token, seq_ids: [0], logits: false)
        }

        batch.pointee.logits?[Int(batch.pointee.n_tokens - 1)] = setLogits ? 1 : 0

        if llama_decode(context, batch.pointee) != 0 {
            LoggerService.shared.warning("Failed to decode batch")
            return false
        }

        restarted = false
        return true
    }
    
    /// Complete the next token in the sequence
    func completionLoop(maxTokens: Int, currentToken: inout Int) -> String? {
        guard shouldContinueGeneration() else {
            return nil
        }
        guard let context = context,
              let vocab = vocab,
              let sampling = sampling else {
            LoggerService.shared.error("Missing required components for completion")
            return nil
        }
        
        // No longer a while loop. Each call generates one token.
        if currentToken < maxTokens {
            let newTokenId = llama_sampler_sample(sampling, context, -1)
            
            if llama_vocab_is_eog(vocab, newTokenId) {
                LoggerService.shared.info("End of generation token detected")
                temporary_invalid_cchars.removeAll()
                return nil
            }
            
            let tokenStr = token_to_piece(token: newTokenId)
            temporary_invalid_cchars.append(contentsOf: tokenStr)
            let new_token_str: String
            if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
                temporary_invalid_cchars.removeAll()
                new_token_str = string
            } else if (0 ..< temporary_invalid_cchars.count).contains(where: {$0 != 0 && String(validatingUTF8: Array(temporary_invalid_cchars.suffix($0)) + [0]) != nil}) {
                // in this case, at least the suffix of the temporary_invalid_cchars can be interpreted as UTF8 string
                let string = String(cString: temporary_invalid_cchars + [0])
                temporary_invalid_cchars.removeAll()
                new_token_str = string
            } else {
                new_token_str = ""
            }
            var batch = createBatch(batch: 1)
            // Add the sampled token to the batch at position n_cur
            llama_batch_add(batch: &batch, token: newTokenId, seq_ids: [0], logits: true)
            
            if llama_decode(context, batch) != 0 {
                LoggerService.shared.warning("Failed to decode token batch")
                llama_batch_free(batch)
                return nil
            }
            
            currentToken += 1
            llama_batch_free(batch)
            return new_token_str
        }
        
        return nil
    }
    
    /// Add a user message to the context
    func appendUserMessage(userMessage: String) {
        guard shouldContinueGeneration() else {
            LoggerService.shared.warning("Generation cancelled or model unloaded.")
            return
        }

        // Tokenize the user message
        let tokensList = tokenize(text: userMessage, add_bos: false)
        if tokensList.isEmpty {
            LoggerService.shared.warning("User message tokenization resulted in zero tokens.")
            return
        }

        // Reset persistent batch before reusing
        resetPersistentBatch()

        guard let batch = persistentBatch else {
            LoggerService.shared.error("Persistent batch not initialized.")
            return
        }

        // Add tokens to batch safely
        for token in tokensList {
            if batch.pointee.n_tokens >= batchCapacity {
                LoggerService.shared.error("Batch exceeded capacity in appendUserMessage.")
                return
            }
            llama_batch_add(batch: batch, token: token, seq_ids: [0], logits: false)
        }

        // Enable logits calculation on the last token added
        if batch.pointee.n_tokens > 0 {
            batch.pointee.logits?[Int(batch.pointee.n_tokens - 1)] = 1
        } else {
            LoggerService.shared.warning("No tokens added to batch in appendUserMessage.")
            return
        }

        // Perform decode
        if llama_decode(context, batch.pointee) != 0 {
            LoggerService.shared.error("llama_decode failed during appendUserMessage.")
            return
        }
        
        LoggerService.shared.debug("appendUserMessage successfully decoded batch with \(batch.pointee.n_tokens) tokens.")
    }
    
    /// Check if a context reset is needed
    func checkResetPending() -> Bool {
        let size = (n_cur + Int32((LlamaConfig.shared.batchSize + LlamaConfig.shared.maxTokens)))
        LoggerService.shared.debug("checkResetPending: \(size)/\(LlamaConfig.shared.contextSize)")
        return size >= LlamaConfig.shared.contextSize
    }
    
    /// Clear the context and optionally the KV cache
    func clearContext(clearKvCache: Bool = true) {
        guard let context = context else { return }
        llama_kv_self_clear(context)
        
        self.tokens_list.removeAll()
        self.clearBuffers()
        n_cur = 0
        restarted = true
    }
    
    /// Clear the KV cache
    func clearKVCache() {
        guard let context = context else { return }
        llama_kv_self_clear(context)
    }
    
    /// Keep a specific sequence in the KV cache
    func keepSequence(_ sequenceId: Int32) {
        guard let context = context else { return }
        llama_kv_self_seq_keep(context, sequenceId)
    }
    
    /// Get information about the KV cache usage
    func getKVCacheInfo() -> (usedCells: Int32, tokenCount: Int32)? {
        guard let context = context else { return nil }
        return (
            llama_kv_self_used_cells(context),
            llama_kv_self_n_tokens(context)
        )
    }
    
    /// Clean up all resources used by this model
    func cleanup() async {
        // Set cancelled flag asynchronously to avoid deadlocks
        setCancelled(true)
        
        // Perform the cleanup on our operation queue
        await withCheckedContinuation { continuation in
            self.cleanupInternal()
            continuation.resume()
        }
    }
    
    /// Internal cleanup implementation - must be called on operation queue
    private func cleanupInternal() {
        LoggerService.shared.debug("Starting cleanup process for model \(self.id)...")
        
        self.n_cur = 0
        self.effectivePos = 0
        
        // Free LoRA adapters first
        if self.context != nil {
            LoggerService.shared.debug("Clearing LoRA adapters...")
            self.clearAllLoRAAdapters()
        }
        
        // Clear buffers
        self.tokens_list.removeAll(keepingCapacity: true)
        self.temporary_invalid_cchars.removeAll(keepingCapacity: true)
        
        // Free sampler
        if self.sampling != nil {
            LoggerService.shared.debug("Freeing sampler...")
            self.freeSampler()
        }
        
        // Free context
        if self.context != nil {
            LoggerService.shared.debug("Clearing KV cache...")
            llama_kv_self_clear(self.context)
            
            LoggerService.shared.debug("Freeing context...")
            llama_free(self.context)
            self.context = nil
        }
        
        // Release shared weights instead of freeing model directly
        if let weights = self.sharedWeights {
            LoggerService.shared.debug("Releasing shared weights...")
            Task {
                await LlamaBridge.shared.releaseWeights(weights)
            }
            self.sharedWeights = nil
        }
        
        // Set references to nil without freeing
        self.model = nil
        self.vocab = nil
        
        // Reset other state
        self.shouldLoadLora = true
        self.restarted = true
        
        // Free persistent batch
        if let batch = self.persistentBatch {
            LoggerService.shared.debug("Freeing persistent batch...")
            llama_batch_free(batch.pointee)
            batch.deinitialize(count: 1)
            batch.deallocate()
            self.persistentBatch = nil
        }
        
        LoggerService.shared.debug("Cleanup process completed for model \(self.id)")
        
        // Update state after cleanup
        self.updateState(.unloaded)
    }
    
    /// Clean up buffers but don't free the model
    func clearBuffers() {
        tokens_list.removeAll(keepingCapacity: true)
        temporary_invalid_cchars.removeAll(keepingCapacity: true)
    }
    
    // MARK: - Private Model Management Methods
    
    /// Create a context from a loaded model
    private func createContext(model: OpaquePointer, path: String) {
        setCancelled(false)
        
        var params = llama_context_default_params()
        params.n_ctx = UInt32(LlamaConfig.shared.contextSize + LlamaConfig.shared.batchSize)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        params.n_threads_batch = params.n_threads
        params.flash_attn = false
        
        // Use llama_new_context_with_model for shared model approach
        guard let newContext = llama_init_from_model(model, params) else {
            LoggerService.shared.warning("Could not load context!")
            return
        }
        context = newContext
        
        // Reinitialize persistent batch here (fresh allocation)
        initializePersistentBatch()
    }
    
    /// Initialize the persistent batch
    private func initializePersistentBatch() {
        if persistentBatch == nil {
            persistentBatch = UnsafeMutablePointer<llama_batch>.allocate(capacity: 1)
            persistentBatch?.initialize(to: llama_batch_init(batchCapacity, 0, 1))
            LoggerService.shared.debug("✅ Persistent batch allocated and initialized.")
        }
    }
    
    /// Reset the persistent batch to empty
    private func resetPersistentBatch() {
        guard let batch = persistentBatch else { return }
        batch.pointee.n_tokens = 0
    }
    
    // MARK: - Sampler Management
    
    /// Create the default sampler based on configuration
    private func createDefaultSampler() {
        freeSampler()
        
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        
        if LlamaConfig.shared.temperature == 0.0 {
            // Use greedy sampling for temperature 0
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            let vcab = vocab
            let ctx = context
            if (vocab != nil && ctx != nil) {
                let dry = llama_sampler_init_dry(vcab, 0, LlamaConfig.shared.dryMultiplier, LlamaConfig.shared.dryBase, 2, 1024, nil, 0)
                llama_sampler_chain_add(chain, dry)
            }
            let topP = llama_sampler_init_top_p(LlamaConfig.shared.topP, 2)
            llama_sampler_chain_add(chain, topP)
            let minP = llama_sampler_init_min_p(LlamaConfig.shared.minP, 2)
            llama_sampler_chain_add(chain, minP)
            
            let temp = llama_sampler_init_temp(LlamaConfig.shared.temperature)
            llama_sampler_chain_add(chain, temp)
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: UInt32.min ... UInt32.max)))
        }
        
        sampling = chain
    }
    
    /// Update the sampler based on current configuration
    private func updateSampler() {
        if (sampling != nil) {
            freeSampler()
        }
        if (sampling == nil) {
            createDefaultSampler()
        }
    }
    
    /// Free the current sampler
    private func freeSampler() {
        if let sampler = sampling {
            llama_sampler_free(sampler)
            sampling = nil
            LoggerService.shared.debug("Sampler freed.")
        }
    }
    
    // MARK: - LoRA Adapter Management
    
    /// Load the LoRA adapter for an agent
    private func loadLoraForAgent(from agent: String) async {
 
        let loraPath = agent
        
        // Set flag to avoid reloading in completion
        await Task {
            self.shouldLoadLora = false
            
            // Ensure we don't reload the same LoRA adapter
            if (self.loraAdapters.keys.count == 1 && self.loraAdapters.keys.contains(loraPath)) {
                return
            }
            
            // Clear previous adapters
            self.clearAllLoRAAdapters()
            
            guard FileManager.default.fileExists(atPath: loraPath) else {
                LoggerService.shared.debug("❌ No LoRA adapter found at path: \(loraPath)")
                return
            }
            
            // Load LoRA
            self.loadLoRAAdapter(from: loraPath)
            LoggerService.shared.debug("✅ Loaded LoRA adapter from \(loraPath)")
        }.value
    }
    
    /// Load a specific LoRA adapter
    private func loadLoRAAdapter(from loraPath: String) {
        guard let model = model else {
            LoggerService.shared.debug("❌ No model loaded, cannot load LoRA adapter.")
            return
        }
        
        guard let adapterPtr = llama_adapter_lora_init(model, loraPath) else {
            LoggerService.shared.debug("❌ Failed to initialize LoRA adapter at \(loraPath)")
            return
        }
        guard let ctx = context else {
            LoggerService.shared.warning("❌ No context available to set LoRA adapter.")
            return
        }
        llama_set_adapter_lora(ctx, adapterPtr, LlamaConfig.shared.loraScale)
    }
    
    /// Remove a specific LoRA adapter
    private func removeLoRAAdapter(_ loraPath: String) -> Bool {
        guard let ctx = context else {
            LoggerService.shared.warning("❌ No context available to remove LoRA adapter.")
            return false
        }
        guard let adapterPtr = loraAdapters[loraPath] else {
            LoggerService.shared.warning("❌ LoRA adapter '\(loraPath)' not found or never loaded.")
            return false
        }
        
        let result = llama_rm_adapter_lora(ctx, adapterPtr)
        if result == -1 {
            LoggerService.shared.warning("❌ Adapter '\(loraPath)' is not present in the context.")
            return false
        }
        
        LoggerService.shared.debug("✅ Removed LoRA adapter '\(loraPath)' from context.")
        return true
    }
    
    /// Clear all loaded LoRA adapters
    private func clearAllLoRAAdapters() {
        guard let ctx = context else {
            LoggerService.shared.debug("No context available when clearing LoRA adapters")
            return
        }
        
        // First remove from context
        LoggerService.shared.debug("Removing all LoRA adapters from context...")
        llama_clear_adapter_lora(ctx)
        
        // Explicitly free each adapter
        for (path, adapter) in loraAdapters {
            if let adapter = adapter {
                LoggerService.shared.debug("Freeing LoRA adapter: \(path)")
                llama_adapter_lora_free(adapter)
            }
        }
        
        loraAdapters.removeAll()
    }
    
    // MARK: - Batch Management
    
    /// Create a new batch with specified capacity
    private func createBatch(batch: Int32) -> llama_batch {
        return llama_batch_init(batch, 0, 1)
    }
    
    /// Free a batch
    private func freeBatch(_ batch: inout llama_batch) {
        // Free sequence ID arrays
        if let seq_id = batch.seq_id {
            for i in 0..<Int(batch.n_tokens) {
                seq_id[i]?.deallocate()
            }
            seq_id.deallocate()
        }
        
        // Free other components
        batch.token?.deallocate()
        batch.pos?.deallocate()
        batch.n_seq_id?.deallocate()
        batch.logits?.deallocate()
    }
    
    /// Add a token to a batch
    private func llama_batch_add(batch: UnsafeMutablePointer<llama_batch>, token: llama_token, seq_ids: [llama_seq_id], logits: Bool) {
        let i = Int(batch.pointee.n_tokens)
        guard i < batchCapacity else {
            LoggerService.shared.error("Attempt to add token beyond batch capacity")
            return
        }
        
        batch.pointee.token?[i] = token
        batch.pointee.pos?[i] = n_cur
        batch.pointee.n_seq_id?[i] = Int32(seq_ids.count)
        for (j, seq_id) in seq_ids.enumerated() {
            batch.pointee.seq_id?[i]?[j] = seq_id
        }
        batch.pointee.logits?[i] = logits ? 1 : 0
        
        batch.pointee.n_tokens += 1
        n_cur += 1
        effectivePos += 1
    }
    
    // MARK: - Tokenization and Text Processing
    
    /// Tokenize text into token IDs
    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        guard let vocab = vocab else {
            LoggerService.shared.warning("Error: Vocab not available")
            return []
        }
        
        // Use pre-allocated buffer instead of dynamic allocation
        let utf8Count = text.utf8.count
        let n_tokens = min(utf8Count + (add_bos ? 1 : 0) + 1, maxTokens)
        
        let tokenCount = llama_tokenize(
            vocab,
            text,
            Int32(utf8Count),
            tokenBuffer.baseAddress,
            Int32(n_tokens),
            false,
            true
        )
        
        // Create array from buffer slice
        if tokenCount > 0 {
            return Array(tokenBuffer[..<Int(tokenCount)])
        }
        return []
    }
    
    /// Convert a token ID to a piece of text
    private func token_to_piece(token: llama_token) -> [CChar] {
        guard let vocab = vocab else {
            LoggerService.shared.error("Error: Vocab not available")
            return []
        }
        
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer {
            result.deallocate()
        }
        
        // Use vocab-based conversion
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)
        
        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer {
                newResult.deallocate()
            }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, false)
            let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
            return Array(bufferPointer)
        } else {
            let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
            return Array(bufferPointer)
        }
    }
    
    // MARK: - Deinitialization
    
    deinit {
        // Clean up allocated resources
        tokenBuffer.deallocate()
        LoggerService.shared.debug("LlamaModel \(id) deallocated")
    }
}
