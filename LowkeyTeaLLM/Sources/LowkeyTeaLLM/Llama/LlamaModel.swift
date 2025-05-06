import Foundation
import llama

/// An actor representing shared model weights for llama models
/// Multiple LlamaModel instances can share these weights
public actor LlamaModel {
    /// Unique identifier for this weights instance
    nonisolated let id: String
    
    /// Path to the model file - stored in a class to allow nonisolated access
    private class PathContainer {
        let path: String
        
        init(path: String) {
            self.path = path
        }
    }
    
    /// Container for path to allow nonisolated access
    nonisolated private let pathContainer: PathContainer
    
    /// Path to the model file - nonisolated getter for external access
    nonisolated var modelPath: String {
        return pathContainer.path
    }
    
    /// Llama model pointer - isolated within actor
    private var modelPointer: OpaquePointer?
    
    /// Vocabulary for the model - isolated within actor
    private var vocabPointer: OpaquePointer?
    
    /// Reference count to track usage
    private var referenceCount: Int = 0
    
    /// Initialize with a model path
    init(id: String, path: String) throws {
        self.id = id
        self.pathContainer = PathContainer(path: path)
        
        // We'll load the model directly in the initializer
        // This avoids calling actor-isolated methods from init
        var params = llama_model_default_params()
        if LlamaConfig.shared.useMetalGPU {
            params.n_gpu_layers = 30
        } else {
            params.n_gpu_layers = 0
        }
        
        guard let newModel = llama_model_load_from_file(path, params) else {
            throw LlamaError.modelNotLoaded
        }
        
        modelPointer = newModel
        vocabPointer = llama_model_get_vocab(newModel)
        
        LoggerService.shared.info("LlamaModel \(id) initialized from \(path)")
    }
    
    /// Optional method to reload the model if needed
    func reloadModel() throws {
        var params = llama_model_default_params()
        if LlamaConfig.shared.useMetalGPU {
            params.n_gpu_layers = 30
        } else {
            params.n_gpu_layers = 0
        }
        
        // Use the path from our container
        let path = pathContainer.path
        guard let newModel = llama_model_load_from_file(path, params) else {
            throw LlamaError.modelNotLoaded
        }
        
        // Free existing model if it exists
        if let model = modelPointer {
            llama_model_free(model)
        }
        
        modelPointer = newModel
        vocabPointer = llama_model_get_vocab(newModel)
    }
    
    /// Increment reference count - must be called with await
    func retain() {
        referenceCount += 1
        LoggerService.shared.debug("LlamaModel \(id) retained, count: \(referenceCount)")
    }
    
    /// Decrement reference count, free resources if zero - must be called with await
    func release() {
        referenceCount -= 1
        LoggerService.shared.debug("LlamaModel \(id) released, count: \(referenceCount)")
        
        if referenceCount <= 0 {
            cleanup()
        }
    }
    
    /// Get the current reference count - must be called with await
    var refCount: Int {
        return referenceCount
    }
    
    /// Access method for model - must be called with await
    func getModel() -> OpaquePointer? {
        return modelPointer
    }
    
    /// Access method for vocab - must be called with await
    func getVocab() -> OpaquePointer? {
        return vocabPointer
    }
    
    /// Free model resources - internal actor-isolated function
    func cleanup() {
        if let model = modelPointer {
            llama_model_free(model)
            modelPointer = nil
            vocabPointer = nil
            LoggerService.shared.info("LlamaModel \(id) deallocated")
        }
    }
}
