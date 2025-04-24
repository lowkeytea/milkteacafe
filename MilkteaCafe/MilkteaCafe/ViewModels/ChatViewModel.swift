import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    /// When true, plays sentences via KokoroEngine
    @Published var ttsEnabled: Bool = false
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    /// Tracks if a generation is in progress
    @Published var isGenerating: Bool = false
    /// Tracks if audio playback is in progress
    @Published var isPlaying: Bool = false
    /// The active generation task, for cancellation
    private var generationTask: Task<Void, Never>?
    /// True if we expect a playback to start after generation (TTS enabled run)
    private var expectingPlayback: Bool = false

    private let manager = ModelManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to KokoroEngine playback state to update isPlaying and clear generation flag when playback starts
        KokoroEngine.playbackBus.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                if state != .idle {
                    // Audio is starting or playing
                    self.isPlaying = true
                    // If waiting for playback after generation, clear generation
                    if self.expectingPlayback {
                        self.isGenerating = false
                        self.expectingPlayback = false
                    }
                } else {
                    // Audio stopped
                    self.isPlaying = false
                }
            }
            .store(in: &cancellables)
        // Reset conversation when model changes
        manager.$selectedModelId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newModel in
                self?.messages.removeAll()
                LoggerService.shared.debug("ChatViewModel: selectedModelId changed to \(newModel ?? "nil"), conversation reset")
            }
            .store(in: &cancellables)
    }

    /// Cancel any ongoing generation or playback
    func cancelGeneration() async {
        // Reset expected playback since run cancelled
        expectingPlayback = false
        LoggerService.shared.info("ChatViewModel: requesting generation cancel…")
        // Cancel LLM generation if active
        if let task = generationTask {
            task.cancel()
            _ = await task.result
            generationTask = nil
        }
        // Stop any in-flight TTS playback
        KokoroEngine.sharedInstance.stop()
        // Update state to reflect that generation has stopped
        self.isGenerating = false
        LoggerService.shared.debug("ChatViewModel: generation and playback fully cancelled")
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Cancel any previous generation
        // Obtain llama instance for selected model
        guard let modelId = manager.selectedModelId,
              let info = manager.modelInfos.first(where: { $0.id == modelId }),
              let llama = manager.llamaModel(for: info.descriptor) else {
            LoggerService.shared.error("ChatViewModel: failed to get LlamaModel for selectedModelId: \(manager.selectedModelId ?? "nil")")
            return
        }
        llama.setCancelled(true)
        await cancelGeneration()
        LoggerService.shared.debug("ChatViewModel.send() called with inputText: '\(text)' and messages: \(messages.count) so far")
        // Append user message
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        LoggerService.shared.debug("ChatViewModel: appended user message, total messages now \(messages.count)")
        inputText = ""

        LoggerService.shared.info("ChatViewModel: starting generation for modelId: \(modelId)")
        llama.setCancelled(false)
        // Indicate that generation is starting and whether we expect playback
        self.isGenerating = true
        expectingPlayback = self.ttsEnabled
        // Start new generation task
        generationTask = Task { [weak self] in
            guard let self = self else { return }
            // Prepare history excluding the new user message
            let history = Array(self.messages.dropLast())

            // Append assistant placeholder
            await MainActor.run {
                self.messages.append(ChatMessage(role: .assistant, content: ""))
                LoggerService.shared.debug("ChatViewModel: appended assistant placeholder, index \(self.messages.count - 1)")
            }

            // Choose filter: sentences if TTS enabled else pass-through tokens
            let filter: TokenFilter = self.ttsEnabled ? SentenceFilter(minLength: LlamaConfig.shared.minParagraphLength) : PassThroughFilter()
            // Stream units via ResponseGenerator
            let stream = await ResponseGenerator.shared.generate(
                llama: llama,
                history: history,
                newUserMessage: userMessage,
                filter: filter
            )

            for await unit in stream {
                LoggerService.shared.debug("ChatViewModel: received unit: '\(unit)' (\(unit.count) chars)")
                await MainActor.run {
                    guard let lastIdx = self.messages.indices.last,
                          self.messages[lastIdx].role == .assistant else {
                        return
                    }
                    self.messages[lastIdx].content += unit
                    LoggerService.shared.debug("ChatViewModel: updated assistant content to: '\(self.messages[lastIdx].content)'")
                }
                // Play via TTS if enabled and using sentence filter
                if self.ttsEnabled {
                    Task.detached {
                        await KokoroEngine.sharedInstance.play(unit)
                    }
                }
            }
            LoggerService.shared.info("ChatViewModel: generation stream finished, messages count: \(self.messages.count)")

            // Trim older messages
            await MainActor.run {
                self.trimHistory()
                LoggerService.shared.debug("ChatViewModel: trimmed history, messages count now: \(self.messages.count)")
                // Clear generationTask from self after completion
                self.generationTask = nil
                // Update state to reflect that generation has finished
                // If no playback is expected, clear generation; else playbackBus will clear it
                if !self.expectingPlayback {
                    self.isGenerating = false
                }
            }
        }
    }

    private func trimHistory() {
        let maxMessages = LlamaConfig.shared.historyMessageCount * 2
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
}
