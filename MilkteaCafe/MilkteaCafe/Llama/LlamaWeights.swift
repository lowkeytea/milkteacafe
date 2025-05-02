import Foundation
import llama

/// A class representing shared model weights for llama models
/// Multiple LlamaModel instances can share these weights
final class LlamaWeights {
    /// Unique identifier for this weights instance
    let id: String
    
    /// Path to the model file
    private(set) var modelPath: String
    
    /// Llama model pointer
    private(set) var model: OpaquePointer!
    
    /// Vocabulary for the model
    private(set) var vocab: OpaquePointer!
    
    /// Reference count to track usage
    private var referenceCount: Int = 0
    
    /// Thread lock for reference counting
    private let lock = NSLock()
    
    /// Initialize with a model path
    init(id: String, path: String) throws {
        self.id = id
        self.modelPath = path
        try loadModelInternal()
        LoggerService.shared.info("LlamaWeights \(id) initialized from \(path)")
    }
    
    /// Load the model from file
    private func loadModelInternal() throws {
        var params = llama_model_default_params()
        if LlamaConfig.shared.useMetalGPU {
            params.n_gpu_layers = 40
        } else {
            params.n_gpu_layers = 0
        }
        
        guard let newModel = llama_model_load_from_file(modelPath, params) else {
            throw LlamaError.modelNotLoaded
        }
        
        model = newModel
        vocab = llama_model_get_vocab(newModel)
    }
    
    /// Increment reference count
    func retain() {
        lock.lock()
        defer { lock.unlock() }
        referenceCount += 1
        LoggerService.shared.debug("LlamaWeights \(id) retained, count: \(referenceCount)")
    }
    
    /// Decrement reference count, free resources if zero
    func release() {
        lock.lock()
        defer { lock.unlock() }
        referenceCount -= 1
        LoggerService.shared.debug("LlamaWeights \(id) released, count: \(referenceCount)")
        
        if referenceCount <= 0 {
            cleanup()
        }
    }
    
    /// Get the current reference count
    var refCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return referenceCount
    }
    
    /// Free model resources
    private func cleanup() {
        if model != nil {
            llama_model_free(model)
            model = nil
            vocab = nil
            LoggerService.shared.info("LlamaWeights \(id) deallocated")
        }
    }
    
    deinit {
        cleanup()
    }
}