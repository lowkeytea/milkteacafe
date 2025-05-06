import Foundation
import Combine
import OSLog
import LowkeyTeaLLM

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)  // Added progress information
    case downloaded
    case error(String)
    
    // Helper to get progress safely
    var progress: Double {
        if case .downloading(let progress) = self {
            return progress
        }
        return 0.0
    }
}

enum LoadState: Equatable {
    case unloaded
    case loading
    case loaded
    case contextUnloaded  // New state: model weights loaded but context unloaded
    case error(String)
}

struct ModelInfo: Identifiable, Equatable {
    let id: String
    let descriptor: ModelDescriptor
    var downloadState: DownloadState = .notDownloaded
    var loadState: LoadState = .unloaded
    var contextState: LoadState = .unloaded // Tracks context loading state separately
    var weightsState: LoadState = .unloaded // Tracks weights loading state separately
}

@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var modelInfos: [ModelInfo] = []
    @Published var selectedModelId: String?
    @Published var selectedThinkingModelId: String?

    private let modelsDirectory: URL
    let gemmaModel = ModelDescriptor(
        id: "google_gemma_3_4b",
        displayName: "Gemma 3 4B",
        url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-4b-it-qat-GGUF/resolve/main/google_gemma-3-4b-it-qat-IQ3_XS.gguf")!,
        fileName: "google_gemma-3-4b-it-qat-IQ3_XS.gguf",
        defaultDownloadSize: 2_370_000_000,
        memoryRequirement: "8GB RAM"
    )
    
    private init() {
        // Determine models storage directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Models", isDirectory: true)
        self.modelsDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Define available models - only supporting Gemma 3 4B
        let descriptors: [ModelDescriptor] = [
            ModelDescriptor(
                id: "google_gemma_3_4b",
                displayName: "Gemma 3 4B",
                url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-4b-it-qat-GGUF/resolve/main/google_gemma-3-4b-it-qat-IQ3_XS.gguf")!,
                fileName: "google_gemma-3-4b-it-qat-IQ3_XS.gguf",
                defaultDownloadSize: 2_370_000_000,
                memoryRequirement: "8GB RAM"
            )
        ]

        self.modelInfos = descriptors.map { 
            ModelInfo(
                id: $0.id, 
                descriptor: $0, 
                contextState: .unloaded, 
                weightsState: .unloaded
            ) 
        }
        self.selectedModelId = descriptors.first?.id
        self.selectedThinkingModelId = descriptors.first?.id

        // Check which models are already downloaded
        checkDownloadedStatus()
    }

    private func checkDownloadedStatus() {
        for idx in modelInfos.indices {
            let url = localURL(for: modelInfos[idx].descriptor)
            if FileManager.default.fileExists(atPath: url.path) {
                modelInfos[idx].downloadState = .downloaded
            } else {
                modelInfos[idx].downloadState = .notDownloaded
            }
        }
    }

    func localURL(for descriptor: ModelDescriptor) -> URL {
        return modelsDirectory.appendingPathComponent(descriptor.fileName)
    }

    func download(_ descriptor: ModelDescriptor) {
        LoggerService.shared.info("Starting download for model '\(descriptor.id)'")
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return }
        objectWillChange.send()
        var info = modelInfos[idx]
        info.downloadState = .downloading(progress: 0.0)  // Initialize with 0 progress
        modelInfos[idx] = info

        let remoteURL = descriptor.url
        let destination = localURL(for: descriptor)
        
        // Create a download task that reports progress
        let session = URLSession.shared
        let downloadTask = session.downloadTask(with: remoteURL) { tempURL, response, error in
            Task { @MainActor in
                if let error = error {
                    LoggerService.shared.error("Download error for model '\(descriptor.id)': \(error.localizedDescription)")
                    self.objectWillChange.send()
                    var updatedInfo = self.modelInfos[idx]
                    updatedInfo.downloadState = .error(error.localizedDescription)
                    self.modelInfos[idx] = updatedInfo
                    return
                }
                
                guard let tempURL = tempURL else {
                    LoggerService.shared.error("Download failed: tempURL nil for model '\(descriptor.id)'")
                    self.objectWillChange.send()
                    var updatedInfo = self.modelInfos[idx]
                    updatedInfo.downloadState = .error("Download failed")
                    self.modelInfos[idx] = updatedInfo
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    LoggerService.shared.info("Completed download for model '\(descriptor.id)'")
                    
                    self.objectWillChange.send()
                    var updatedInfo = self.modelInfos[idx]
                    updatedInfo.downloadState = .downloaded
                    self.modelInfos[idx] = updatedInfo
                } catch {
                    LoggerService.shared.error("File move error for model '\(descriptor.id)': \(error.localizedDescription)")
                    self.objectWillChange.send()
                    var updatedInfo = self.modelInfos[idx]
                    updatedInfo.downloadState = .error(error.localizedDescription)
                    self.modelInfos[idx] = updatedInfo
                }
            }
        }
        
        // Setup a URLSessionTaskDelegate to track progress
        _ = downloadTask.progress.observe(\.fractionCompleted) { progress, _ in
            Task { @MainActor in
                guard let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return }
                var info = self.modelInfos[idx]
                
                // Ensure progress is valid (between 0 and 1)
                let progressValue = max(0.0, min(1.0, progress.fractionCompleted))
                
                // Only update if the downloadState is still .downloading
                if case .downloading = info.downloadState {
                    info.downloadState = .downloading(progress: progressValue)
                    self.modelInfos[idx] = info
                    self.objectWillChange.send()
                    
                    LoggerService.shared.debug("Download progress for '\(descriptor.id)': \(progressValue)")
                }
            }
        }
        
        // Start the download
        downloadTask.resume()
    }

    func delete(_ descriptor: ModelDescriptor) {
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return }
        let fileURL = localURL(for: descriptor)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        var info = modelInfos[idx]
        info.downloadState = .notDownloaded
        info.loadState = .unloaded
        info.contextState = .unloaded
        info.weightsState = .unloaded
        modelInfos[idx] = info
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return false }
        if case .downloaded = modelInfos[idx].downloadState {
            return true
        }
        return false
    }
    
    /// Get the current download progress (0.0 to 1.0) for a model
    func downloadProgress(for descriptor: ModelDescriptor) -> Double {
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return 0.0 }
        return modelInfos[idx].downloadState.progress
    }

    func isLoaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return false }
        return modelInfos[idx].loadState == .loaded || modelInfos[idx].weightsState == .loaded
    }
    
    func isModelLoaded(_ modelId: String) -> Bool {
        // First check our infos record based on loadState
        if let idx = modelInfos.firstIndex(where: { $0.id == modelId }),
           modelInfos[idx].weightsState == .loaded {
            return true
        }
        
        // Check with LlamaBridge to see if this model actually has weights loaded
        // We do this asynchronously but don't wait for the result - this is just for state synchronization
        Task {
            if let descriptor = modelInfos.first(where: { $0.id == modelId })?.descriptor,
               await LlamaBridge.shared.getLoadedWeightIds().contains(modelId) {
                // If bridge confirms weights are loaded, sync our state
                await MainActor.run {
                    if let idx = self.modelInfos.firstIndex(where: { $0.id == modelId }) {
                        var info = self.modelInfos[idx]
                        info.weightsState = .loaded
                        // Update combined loadState for backward compatibility
                        info.loadState = info.contextState == .loaded ? .loaded : .contextUnloaded
                        self.modelInfos[idx] = info
                        LoggerService.shared.debug("ModelManager: Synced model state for \(modelId) - weights are loaded")
                    }
                }
            }
        }
        
        // Final check - if it's downloaded, it's potentially usable
        return modelInfos.contains { model in
            model.id == modelId && model.downloadState == .downloaded
        }
    }

    /// Selects and loads the given descriptor into the 'chat' slot via LlamaBridge.
    func loadContextAsChat(_ descriptor: ModelDescriptor) async {
        if (await isContextLoaded(id: "chat")) {
            return
        }
        selectedModelId = descriptor.id
        if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
            var info = modelInfos[idx]
            info.loadState = .loading
            info.contextState = .loading
            modelInfos[idx] = info
        }
        let path = localURL(for: descriptor).path
        do {
            // Verify the file exists before attempting to load
            if !FileManager.default.fileExists(atPath: path) {
                throw LlamaError.fileNotFound(path: path)
            }
            
            // First ensure weights are loaded
            _ = try await LlamaBridge.shared.loadModelWeights(modelPath: path, weightId: descriptor.id)
            
            // Then load the context
            let context = await LlamaBridge.shared.getContext(id: "chat", path: path)
            let success = await context.loadModel(modelPath: path)
            
            await MainActor.run {
                if let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                    var info = self.modelInfos[idx]
                    info.contextState = success ? .loaded : .error("Failed to load context")
                    info.weightsState = .loaded
                    info.loadState = success ? .loaded : .contextUnloaded
                    self.modelInfos[idx] = info
                }
            }
        } catch {
            await MainActor.run {
                if let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                    var info = self.modelInfos[idx]
                    info.contextState = .error(error.localizedDescription)
                    info.weightsState = .error(error.localizedDescription)
                    info.loadState = .error(error.localizedDescription)
                    self.modelInfos[idx] = info
                }
            }
            
            LoggerService.shared.error("Failed to load model context: \(error.localizedDescription)")
        }
    }

    /// Selects and loads the given descriptor into the 'thinking' slot via LlamaBridge.
    func loadContextAsThinking(_ descriptor: ModelDescriptor) async {
        if (await isContextLoaded(id: "thinking")) {
            return
        }
        selectedThinkingModelId = descriptor.id
        if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
            var info = modelInfos[idx]
            info.loadState = .loading
            info.contextState = .loading
            modelInfos[idx] = info
        }
        let path = localURL(for: descriptor).path
        Task.detached(priority: .userInitiated) {
            do {
                // Verify the file exists before attempting to load
                if !FileManager.default.fileExists(atPath: path) {
                    throw LlamaError.fileNotFound(path: path)
                }
                
                // First ensure weights are loaded
                _ = try await LlamaBridge.shared.loadModelWeights(modelPath: path, weightId: descriptor.id)
                
                // Then load the context
                let context = await LlamaBridge.shared.getContext(id: "thinking", path: path)
                let success = await context.loadModel(modelPath: path)
                
                await MainActor.run {
                    if let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                        var info = self.modelInfos[idx]
                        info.contextState = success ? .loaded : .error("Failed to load context")
                        info.weightsState = .loaded
                        info.loadState = success ? .loaded : .contextUnloaded
                        self.modelInfos[idx] = info
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                        var info = self.modelInfos[idx]
                        info.contextState = .error(error.localizedDescription)
                        info.weightsState = .error(error.localizedDescription)
                        info.loadState = .error(error.localizedDescription)
                        self.modelInfos[idx] = info
                    }
                }
                
                LoggerService.shared.error("Failed to load thinking model context: \(error.localizedDescription)")
            }
        }
    }

    /// Unload the 'chat' or 'thinking' slot context if this descriptor was loaded there.
    /// Preserves the model weights for reuse.
    func unloadContext(_ descriptor: ModelDescriptor) {
        // Unload chat context if this descriptor was the selected chat model
        if selectedModelId == descriptor.id {
            if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                var info = modelInfos[idx]
                info.contextState = .unloaded
                info.loadState = .contextUnloaded // Mark as context unloaded but weights still loaded
                modelInfos[idx] = info
            }
            Task {
                await LlamaBridge.shared.unloadContext(id: "chat")
            }
        }
        
        // Unload thinking context if this descriptor was the selected thinking model
        if selectedThinkingModelId == descriptor.id {
            if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                var info = modelInfos[idx]
                info.contextState = .unloaded
                info.loadState = .contextUnloaded // Mark as context unloaded but weights still loaded
                modelInfos[idx] = info
            }
            Task {
                await LlamaBridge.shared.unloadContext(id: "thinking")
            }
        }
    }
    
    /// Completely unload both context and weights for a model
    func unloadModelComplete(_ descriptor: ModelDescriptor) {
        // First unload the contexts
        unloadContext(descriptor)
        
        // Then unload the weights
        if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
            var info = modelInfos[idx]
            info.weightsState = .unloaded
            info.loadState = .unloaded
            modelInfos[idx] = info
            
            Task {
                _ = await LlamaBridge.shared.unloadModelWeights(weightId: descriptor.id)
            }
        }
        
        // Clear selection if this was a selected model
        if selectedModelId == descriptor.id {
            selectedModelId = nil
        }
        if selectedThinkingModelId == descriptor.id {
            selectedThinkingModelId = nil
        }
    }
    
    // MARK: - Dynamic Thinking Model Management
    
    /**
     * Dynamic Thinking Model Loading System
     *
     * This system optimizes memory usage by only loading the thinking model context when needed
     * and unloading it when idle, while preserving the model weights for quick reuse.
     *
     * Key components:
     * - Reference counting: Tracks how many operations are using the thinking model
     * - Acquisition: Loads model context when needed (creates new context if needed)
     * - Release: Unloads model context when all operations complete (preserves weights)
     * - Thread safety: All operations are MainActor protected with async/await
     * - Error handling: Ensures proper cleanup even when operations fail
     */
    
    /// Track number of active thinking operations
    private(set) var thinkingModelOperationCount = 0
    private var thinkingModelLoadTask: Task<Void, Never>?
    
    /// Check if thinking model context is currently in use
    var isThinkingModelInUse: Bool {
        return thinkingModelOperationCount > 0
    }
    
    /// Increment reference counter and load thinking model context if needed
    func acquireThinkingModel(modelId: String? = nil) async -> Bool {
        let targetModelId = modelId ?? modelInfos.first(where: { $0.id == "google_gemma_3_4b" })?.id
        guard let targetModelId = targetModelId,
              let descriptor = modelInfos.first(where: { $0.id == targetModelId })?.descriptor else {
            LoggerService.shared.error("Failed to acquire thinking model: no suitable model found")
            return false
        }
        
        // Increment counter
        thinkingModelOperationCount += 1
        LoggerService.shared.debug("Thinking model operation count: \(thinkingModelOperationCount)")
        
        // If already loaded with correct model (both weights and context), we're done
        if selectedThinkingModelId == targetModelId, let idx = modelInfos.firstIndex(where: { $0.id == targetModelId }),
           modelInfos[idx].contextState == .loaded {
            LoggerService.shared.debug("Thinking model context already loaded: \(targetModelId)")
            return true
        }
        
        // If already loading, wait for completion
        if let loadTask = thinkingModelLoadTask {
            LoggerService.shared.debug("Waiting for existing thinking model load task")
            _ = await loadTask.value
            return await isContextLoaded(id: "thinking")
        }
        
        // Check if we need to reload weights or just recreate context
        let hasLoadedWeights = await LlamaBridge.shared.getLoadedWeightIds().contains(targetModelId)
        
        // Load the model
        if !hasLoadedWeights {
            LoggerService.shared.info("Loading thinking model weights and context from scratch: \(targetModelId)")
            thinkingModelLoadTask = Task {
                await loadContextAsThinking(descriptor)
                self.thinkingModelLoadTask = nil
            }
        } else {
            LoggerService.shared.info("Creating thinking model context using existing weights: \(targetModelId)")
            thinkingModelLoadTask = Task {
                let context = await LlamaBridge.shared.getContext(id: "thinking", path: localURL(for: descriptor).path)
                let success = await context.loadModel(modelPath: localURL(for: descriptor).path)
                await MainActor.run {
                    if let idx = self.modelInfos.firstIndex(where: { $0.id == targetModelId }) {
                        var info = self.modelInfos[idx]
                        info.contextState = success ? .loaded : .error("Failed to create context")
                        info.loadState = success ? .loaded : .contextUnloaded
                        self.modelInfos[idx] = info
                    }
                    selectedThinkingModelId = targetModelId
                }
                self.thinkingModelLoadTask = nil
            }
        }
        
        // Wait for loading to complete
        _ = await thinkingModelLoadTask?.value
        return await isContextLoaded(id: "thinking")
    }
    
    /// Helper to check if a specific context is loaded
    private func isContextLoaded(id: String) async -> Bool {
        return await LlamaBridge.shared.isContextLoaded(id: id)
    }
    
    /// Decrement reference counter and unload thinking context if unused
    func releaseThinkingModel() async {
        guard thinkingModelOperationCount > 0 else { 
            LoggerService.shared.warning("Attempted to release thinking model with count already at 0")
            return 
        }
        
        // Decrement counter
        thinkingModelOperationCount -= 1
        LoggerService.shared.debug("Thinking model operation count: \(thinkingModelOperationCount)")
        
        // If still in use, keep loaded
        if thinkingModelOperationCount > 0 {
            LoggerService.shared.debug("Thinking model still in use by \(thinkingModelOperationCount) operations")
            return
        }
        
        // Unload context if no longer in use
        if let modelId = selectedThinkingModelId {
            LoggerService.shared.info("Unloading thinking model context: \(modelId)")
            await unloadThinkingModelContext()
        }
    }
    
    /// Unload only the thinking model context while preserving weights
    func unloadThinkingModelContext() async {
        if let modelId = selectedThinkingModelId {
            // Update model info state to reflect context unloaded but weights preserved
            if let idx = modelInfos.firstIndex(where: { $0.id == modelId }) {
                var info = modelInfos[idx]
                info.contextState = .unloaded
                info.loadState = .contextUnloaded
                modelInfos[idx] = info
            }
            
            // Don't clear the selectedThinkingModelId - this helps the ModelManager
            // understand that the model weights are still loaded
            
            // Special handling to only unload the context but keep the weights
            await LlamaBridge.shared.unloadContext(id: "thinking")
            
            LoggerService.shared.info("Thinking model context unloaded, but keeping weights loaded and tracked")
        }
    }
    
    /// Completely unload thinking model, including weights
    func unloadThinkingModelWeights() async {
        if let modelId = selectedThinkingModelId {
            // First ensure context is unloaded
            await unloadThinkingModelContext()
            
            // Then unload weights
            if let idx = modelInfos.firstIndex(where: { $0.id == modelId }) {
                var info = modelInfos[idx]
                info.weightsState = .unloaded
                info.loadState = .unloaded
                modelInfos[idx] = info
            }
            
            // Now unload the weights
            _ = await LlamaBridge.shared.unloadModelWeights(weightId: modelId)
            
            // Clear the selection
            selectedThinkingModelId = nil
            
            LoggerService.shared.info("Thinking model weights completely unloaded: \(modelId)")
        }
    }
} 
