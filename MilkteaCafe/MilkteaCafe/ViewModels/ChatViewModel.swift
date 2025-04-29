import Foundation
import Combine
import MilkteaLlamaKokoro

@MainActor
final class ChatViewModel: ObservableObject {
    /// When true, plays sentences via KokoroEngine
    @Published var ttsEnabled: Bool = UserDefaults.standard.bool(forKey: "ttsEnabled") {
        didSet {
            UserDefaults.standard.set(ttsEnabled, forKey: "ttsEnabled")
        }
    }
    @Published var viewableMessages: [ViewableMessage] = []
    @Published var inputText: String = ""
    /// Tracks if a generation is in progress
    @Published var isGenerating: Bool = false
    /// Tracks if audio playback is in progress
    @Published var isPlaying: Bool = false
    /// Last thinking model output
    @Published var thinkingOutput: String = ""
    /// The active generation task, for cancellation
    private var generationTask: Task<Void, Never>?
    /// True if we expect a playback to start after generation (TTS enabled run)
    private var expectingPlayback: Bool = false
    @Published var thinkingTone: String = ""
    // Customizable prompts
    @Published var thinkingPromptTemplate: String = "You judge sentiment and how long replies should be. If a user is asking for details it the reply request should be a long response. If it is purely conversational it should be a short response. Decide if the next reply should be short or long based on the conversation history so far: \n\n**\n{prompt}\n**\n\nProvide a single sentence on sentiment rating of the conversation. Then provide a single sentence that states 'You should reply with a short response.' or 'You should reply with a long response.'"
    @Published var chatPromptTemplate: String = "Instructions: {tone}\n\nUser Prompt: {prompt}"
    // System prompts configurable via Settings
    @Published var thinkingSystemPrompt: String = "You are an expert analyzer of user prompts."
    @Published var chatSystemPrompt: String = "You are the embodiment of everything Monday stands for. You also love coffee."
    @Published var activeActionGroup: ChatResponseActionGroup?
    /// Available TTS voices
    var availableVoices: [String] { KokoroEngine.sharedInstance.getAvailableVoices() }
    @Published var selectedVoiceName: String = UserDefaults.standard.string(forKey: "selectedVoiceName")
        ?? KokoroEngine.sharedInstance.getCurrentVoice() {
        didSet {
            UserDefaults.standard.set(selectedVoiceName, forKey: "selectedVoiceName")
            Task { await KokoroEngine.sharedInstance.setVoice(selectedVoiceName) }
        }
    }
    // Decision response timer and probability settings
    @Published var decisionInterval: TimeInterval = 15.0
    @Published var decisionProbability: Double = 5.0
    @Published var probabilityIncrement: Double = 25.0

    // Internal state for decision loop
    private var decisionLoopTask: Task<Void, Never>?
    private var decisionResponseGroup: DecisionResponseActionGroup?
    // Ensure initial trigger only runs once when both models have finished loading
    private var didTriggerInitialDecision: Bool = false

    private let manager = ModelManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load persisted chat messages
        loadPersistedChat()

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
        // Reset and reload persisted chat when chat model changes
        manager.$selectedModelId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newModel in
                guard let self = self else { return }
                LoggerService.shared.debug("ChatViewModel: selectedModelId changed to \(newModel ?? "nil"), reloading persisted chat")
                self.loadPersistedChat()
            }
            .store(in: &cancellables)

        // Trigger initial decision only once when both models finish loading
        manager.$modelInfos
            .receive(on: DispatchQueue.main)
            .sink { [weak self] infos in
                guard let self = self else { return }
                // Only fire once when both chat and thinking models are fully loaded
                guard !self.didTriggerInitialDecision,
                      let chatId = self.manager.selectedModelId,
                      let thinkingId = self.manager.selectedThinkingModelId,
                      let chatInfo = infos.first(where: { $0.id == chatId && $0.loadState == .loaded }),
                      let thinkingInfo = infos.first(where: { $0.id == thinkingId && $0.loadState == .loaded })
                else { return }
                self.didTriggerInitialDecision = true
                let initialMsg = self.history.last ?? Message(role: .assistant, category: .chat, content: "", date: Date())
                let group = DecisionResponseActionGroup(
                    viewModel: self,
                    initialProbability: self.decisionProbability,
                    probabilityIncrement: self.probabilityIncrement,
                    startProbability: 100.0
                )
                // Subscribe for TTS playback of the generated response
                group.subscribeToProgress(for: DecisionResponseActionGroup.ActionId.response) { token in
                    Task { @MainActor in
                        if self.ttsEnabled && token.count > 1 {
                            try Task.checkCancellation()
                            await KokoroEngine.sharedInstance.play(token)
                        }
                    }
                }
                self.decisionResponseGroup = group
                Task {
                    await group.execute(with: initialMsg)
                }
            }
            .store(in: &cancellables)

        // Start the periodic decision-response loop
        startDecisionLoop()
    }

    // Load recent persisted messages for the chat view
    private func loadPersistedChat() {
        // Load all persisted chat messages for UI (no limit)
        let raw = MessageStore.shared.getRecentMessages(category: .chat,
                                                        limit: LlamaConfig.shared.historyMessageCount)
        self.viewableMessages = raw.map { ViewableMessage(from: $0) }.sorted(by: { $0.timestamp < $1.timestamp })
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

    @MainActor
    func send() async {
        // Cancel any existing generation or playback
        await cancelGeneration()
        // Reload persisted messages so we have the latest context and clear any previous placeholders
        loadPersistedChat()
        
        // Prepare and validate user input
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Clear input and add user message persistently and to viewable list
        self.inputText = ""
        let userMsg = Message(role: .user, category: .chat, content: text)
        MessageStore.shared.addMessage(userMsg)
        self.viewableMessages.append(ViewableMessage(from: userMsg))
        
        self.isGenerating = true
        self.expectingPlayback = self.ttsEnabled
        self.thinkingTone = ""
        self.thinkingOutput = ""
        
        // Create action group
        let actionGroup = ChatResponseActionGroup(viewModel: self)
        self.activeActionGroup = actionGroup
        
        // Create new message placeholder for assistant response
        let assistantPlaceholder = ViewableMessage(role: .assistant, content: "")
        let assistantIndex = viewableMessages.count
        self.viewableMessages.append(assistantPlaceholder)
        
        // Subscribe to chat tokens for live updates into the placeholder
        actionGroup.subscribeToProgress(for: ChatResponseActionGroup.ActionId.chat) { [weak self] token in
            Task { @MainActor in
                guard let self = self, assistantIndex < self.viewableMessages.count else { return }
                self.viewableMessages[assistantIndex].content += token
                // Handle TTS if enabled
                if self.ttsEnabled && token.count > 1 {
                    try Task.checkCancellation()
                    await KokoroEngine.sharedInstance.play(token)
                }
            }
        }
        
        // Execute the action group
        generationTask = Task {
            do {
                await actionGroup.execute(with: userMsg)
                print("Action group execution completed")
                
                // Clear the reference when done
                await MainActor.run {
                    self.activeActionGroup = nil
                }
            } catch {
                print("Error in action group execution: \(error)")
                
                // Also clear reference on error
                await MainActor.run {
                    self.activeActionGroup = nil
                }
            }
        }
    }

    func clearMessages() async {
        MessageStore.shared.clearMessages()
        await LlamaBridge.shared.clearContext()
        thinkingTone = ""
        thinkingOutput = ""
        loadPersistedChat()
    }
    
    func formatMessages(_ messages: [Message]) -> String {
        messages.map { "The \($0.role.rawValue) said: \($0.content)\n" }
                .joined()
    }

    // Computed context for prompting the LLM based on current viewableMessages
    var history: [Message] {
        viewableMessages.map {
            Message(role: $0.role, category: .chat, content: $0.content, date: $0.timestamp)
        }
    }

    // Cancel the decision loop when view model is deallocated
    deinit {
        decisionLoopTask?.cancel()
    }

    // Loop that rolls for a decision-response action when idle
    private func startDecisionLoop() {
        decisionLoopTask?.cancel()
        // Create a persistent group so its probability state is preserved
        let group = DecisionResponseActionGroup(viewModel: self,
                                                initialProbability: decisionProbability,
                                                probabilityIncrement: probabilityIncrement)
        // Subscribe for TTS playback of the generated response
        group.subscribeToProgress(for: DecisionResponseActionGroup.ActionId.response) { [weak self] token in
            Task { @MainActor in
                if self?.ttsEnabled == true && token.count > 1 {
                    try Task.checkCancellation()
                    await KokoroEngine.sharedInstance.play(token)
                }
            }
        }
        decisionResponseGroup = group
        decisionLoopTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Skip while generating or user typing
                if self.isGenerating || !self.inputText.isEmpty || KokoroEngine.sharedInstance.playbackState == .playing {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                // Wait configured interval
                try? await Task.sleep(nanoseconds: UInt64(self.decisionInterval * 1_000_000_000))
                // Re-check conditions
                if self.isGenerating || !self.inputText.isEmpty {
                    continue
                }
                // Execute decision-response
                let lastMsg = self.history.last ?? Message(role: .assistant,
                                                           category: .chat,
                                                           content: "",
                                                           date: Date())
                await group.execute(with: lastMsg)
            }
        }
    }
}
