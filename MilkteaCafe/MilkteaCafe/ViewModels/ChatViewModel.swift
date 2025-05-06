import Foundation
import Combine
import LowkeyTeaLLM

// MARK: - Notification Names
extension Notification.Name {
    static let chatScrollingStateChanged = Notification.Name("chatScrollingStateChanged")
}

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
    /// Selected tab (0: Chat, 1: Settings)
    @Published var selectedTab: Int = 0
    /// The active generation task, for cancellation
    private var generationTask: Task<Void, Never>?
    /// True if we expect a playback to start after generation (TTS enabled run)
    private var expectingPlayback: Bool = false
    @Published var thinkingTone: String = ""
    @Published var thinkingOutput: String = ""
    // Customizable prompts
    @Published var thinkingPromptTemplate: String = "You judge sentiment and how long replies should be. If a user is asking for details it the reply request should be a long response. If it is purely conversational it should be a short response. Decide if the next reply should be short or long based on the conversation history so far: \n\n**\n{prompt}\n**\n\nProvide a single sentence on sentiment rating of the conversation. Then provide a single sentence that states 'You should reply with a short response.' or 'You should reply with a long response.'"
    @Published var chatPromptTemplate: String = "Instructions: {tone}\n\nUser Prompt: {prompt}"
    // System prompts configurable via Settings
    @Published var thinkingSystemPrompt: String = "You are an expert analyzer of user prompts."
    @Published var chatSystemPrompt: String = UserDefaults.standard.string(forKey: "chatSystemPrompt") ?? "You are the embodiment of everything Monday stands for. You also love coffee."
    @Published var activeActionGroup: FunctionCallActionGroup?
    /// Available TTS voices
    var availableVoices: [String] { KokoroEngine.sharedInstance.getAvailableVoices() }
    @Published var selectedVoiceName: String = UserDefaults.standard.string(forKey: "selectedVoiceName")
        ?? KokoroEngine.sharedInstance.getCurrentVoice() {
        didSet {
            UserDefaults.standard.set(selectedVoiceName, forKey: "selectedVoiceName")
            Task { await KokoroEngine.sharedInstance.setVoice(selectedVoiceName) }
        }
    }
    // Reference to DecisionResponseActionGroup for manual triggering
    private var decisionResponseGroup: DecisionResponseActionGroup?

    private let manager = ModelManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load persisted chat messages
        loadPersistedChat()
        
        // Initialize system prompt from manager
        chatSystemPrompt = SystemPromptManager.shared.getSystemPrompt()
        
        // Listen for system prompt changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemPromptDidChange),
            name: .systemPromptDidChange,
            object: nil
        )
        
        // Listen for voice support setting changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(voiceSupportSettingChanged),
            name: .voiceSupportSettingChanged,
            object: nil
        )
        
        // Subscribe to KokoroEngine playback state to update isPlaying and clear generation flag when playback starts
        KokoroEngine.playbackBus.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                let isAudioActive = state != .idle
                LoggerService.shared.debug("KokoroEngine playback state changed: \(state), active = \(isAudioActive)")
                
                if isAudioActive {
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
            
        // Create decision response group for manual triggering
        self.decisionResponseGroup = DecisionResponseActionGroup(
            viewModel: self,
            initialProbability: 0,
            probabilityIncrement: 0
        )
        
        // Subscribe for TTS playback of the generated response
        self.decisionResponseGroup?.subscribeToProgress(
            for: DecisionResponseActionGroup.ActionId.response
        ) { token in
            Task { @MainActor in
                if self.ttsEnabled && token.count > 1 {
                    try Task.checkCancellation()
                    await KokoroEngine.sharedInstance.play(token)
                }
            }
        }
    }

    // Load recent persisted messages for the chat view
    private func loadPersistedChat() {
        // Load all persisted chat messages for UI (no limit)
        let raw = MessageStore.shared.getRecentMessages(category: .chat,
                                                        limit: 8)
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
        await ModelManager.shared.loadContextAsChat(ModelManager.shared.gemmaModel)
        await ModelManager.shared.loadContextAsThinking(ModelManager.shared.gemmaModel)
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
        let actionGroup = FunctionCallActionGroup(viewModel: self)
        self.activeActionGroup = actionGroup
        
        // Create new message placeholder for assistant response
        let assistantPlaceholder = ViewableMessage(role: .assistant, content: "")
        let assistantIndex = viewableMessages.count
        self.viewableMessages.append(assistantPlaceholder)
        
        // Subscribe to chat tokens for live updates into the placeholder
        actionGroup.subscribeToProgress(for: FunctionCallActionGroup.ActionId.chat) { [weak self] token in
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
                await actionGroup.execute(with: userMsg.toLlamaMessage())
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
    var history: [LlamaMessage] {
        viewableMessages.map {
            LlamaMessage(role: $0.role, category: .chat, content: $0.content, date: $0.timestamp)
        }
    }

    // MARK: - System Prompt Management
    
    /// Updates the system prompt when changed through the SystemPromptManager
    @objc private func systemPromptDidChange(_ notification: Notification) {
        if let newPrompt = notification.userInfo?["prompt"] as? String {
            LoggerService.shared.info("Updating ChatViewModel with new system prompt")
            self.chatSystemPrompt = newPrompt
        }
    }
    
    /// Manual method to update the system prompt
    func updateSystemPrompt(_ prompt: String) {
        // Use the manager to update the prompt
        // This will trigger the notification which updates this instance
        SystemPromptManager.shared.updateSystemPrompt(prompt)
    }
    
    // MARK: - Voice Support Management
    
    /// Updates the voice support setting when changed through a function call
    @objc private func voiceSupportSettingChanged(_ notification: Notification) {
        if let enabled = notification.userInfo?["enabled"] as? Bool {
            LoggerService.shared.info("Updating voice support setting to: \(enabled)")
            self.ttsEnabled = enabled
        }
    }
    
    /// Manual method to update the voice support setting
    func updateVoiceSupport(enabled: Bool) {
        self.ttsEnabled = enabled
    }
    
    // MARK: - Manual Decision Trigger
    
    /// Manually trigger the decision response system
    func triggerDecisionResponse() async {
        let lastMsg = history.last ?? LlamaMessage(role: .assistant, category: .chat, content: "", date: Date())
        await decisionResponseGroup?.execute(with: lastMsg)
    }
}
