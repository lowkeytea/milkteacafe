import Foundation
import Combine
import OSLog

enum DownloadState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case error(String)
}

enum LoadState: Equatable {
    case unloaded
    case loading
    case loaded
    case error(String)
}

struct ModelInfo: Identifiable, Equatable {
    let id: String
    let descriptor: ModelDescriptor
    var downloadState: DownloadState = .notDownloaded
    var loadState: LoadState = .unloaded
}

@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var modelInfos: [ModelInfo] = []
    @Published var selectedModelId: String?
    @Published var selectedThinkingModelId: String?

    private let modelsDirectory: URL

    private init() {
        // Determine models storage directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Models", isDirectory: true)
        self.modelsDirectory = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Define available models
        let descriptors: [ModelDescriptor] = [
            ModelDescriptor(
                id: "google_gemma_3_4b",
                displayName: "Gemma 3 4B",
                url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-4b-it-qat-GGUF/resolve/main/google_gemma-3-4b-it-qat-Q4_0.gguf")!,
                fileName: "google_gemma-3-4b-it-qat-Q4_0.gguf",
                defaultDownloadSize: 2_370_000_000,
                memoryRequirement: "8GB RAM"
            ),
            ModelDescriptor(
                id: "google_gemma_3_1b",
                displayName: "Gemma 3 1B",
                url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-1b-it-qat-GGUF/resolve/main/google_gemma-3-1b-it-qat-Q4_0.gguf")!,
                fileName: "google_gemma-3-1b-it-qat-Q4_0.gguf",
                defaultDownloadSize: 722_000_000,
                memoryRequirement: "4GB RAM"
            ),
            ModelDescriptor(
                id: "google_gemma_3_12b",
                displayName: "Gemma 3 12B",
                url: URL(string: "https://huggingface.co/bartowski/google_gemma-3-12b-it-qat-GGUF/resolve/main/google_gemma-3-12b-it-qat-Q4_0.gguf")!,
                fileName: "google_gemma-3-12b-it-qat-Q4_0.gguf",
                defaultDownloadSize: 6_910_000_000,
                memoryRequirement: "12GB RAM"
            )
        ]

        self.modelInfos = descriptors.map { ModelInfo(id: $0.id, descriptor: $0) }
        self.selectedModelId = descriptors.first?.id

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
        info.downloadState = .downloading
        modelInfos[idx] = info

        let remoteURL = descriptor.url
        let destination = localURL(for: descriptor)

        let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, _, error in
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
        task.resume()
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
        modelInfos[idx] = info
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return false }
        return modelInfos[idx].downloadState == .downloaded
    }

    func isLoaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) else { return false }
        return modelInfos[idx].loadState == .loaded
    }

    /// Selects and loads the given descriptor into the 'chat' slot via LlamaBridge.
    func loadAsChat(_ descriptor: ModelDescriptor) {
        selectedModelId = descriptor.id
        if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
            var info = modelInfos[idx]
            info.loadState = .loading
            modelInfos[idx] = info
        }
        let path = localURL(for: descriptor).path
        Task.detached(priority: .userInitiated) {
            let model = await LlamaBridge.shared.getModel(id: "chat", path: path)
            let success = model.loadModel(modelPath: path)
            await MainActor.run {
                if let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                    var info = self.modelInfos[idx]
                    info.loadState = success ? .loaded : .error("Failed to load model")
                    self.modelInfos[idx] = info
                }
            }
        }
    }

    /// Selects and loads the given descriptor into the 'thinking' slot via LlamaBridge.
    func loadAsThinking(_ descriptor: ModelDescriptor) {
        selectedThinkingModelId = descriptor.id
        if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
            var info = modelInfos[idx]
            info.loadState = .loading
            modelInfos[idx] = info
        }
        let path = localURL(for: descriptor).path
        Task.detached(priority: .userInitiated) {
            let model = await LlamaBridge.shared.getModel(id: "thinking", path: path)
            let success = model.loadModel(modelPath: path)
            await MainActor.run {
                if let idx = self.modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                    var info = self.modelInfos[idx]
                    info.loadState = success ? .loaded : .error("Failed to load model")
                    self.modelInfos[idx] = info
                }
            }
        }
    }

    /// Unload the 'chat' or 'thinking' slot if this descriptor was loaded there.
    func unload(_ descriptor: ModelDescriptor) {
        // Unload chat slot if this descriptor was the selected chat model
        if selectedModelId == descriptor.id {
            selectedModelId = nil
            if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                var info = modelInfos[idx]
                info.loadState = .unloaded
                modelInfos[idx] = info
            }
            Task {
                await LlamaBridge.shared.unloadModel(id: "chat")
            }
        }
        // Unload thinking slot if this descriptor was the selected thinking model
        if selectedThinkingModelId == descriptor.id {
            selectedThinkingModelId = nil
            if let idx = modelInfos.firstIndex(where: { $0.id == descriptor.id }) {
                var info = modelInfos[idx]
                info.loadState = .unloaded
                modelInfos[idx] = info
            }
            Task {
                await LlamaBridge.shared.unloadModel(id: "thinking")
            }
        }
    }
} 
