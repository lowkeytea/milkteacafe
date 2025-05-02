import Foundation
import Combine
import MilkteaLlamaKokoro

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
    // Decision response timer and probability settings
    @Published var decisionInterval: TimeInterval = 15.0
    @Published var decisionProbability: Double = 5.0
    @Published var probabilityIncrement: Double = 25.0

    // Internal state for decision loop
    private var decisionLoopTask: Task<Void, Never>?
    private var decisionResponseGroup: DecisionResponseActionGroup?
    // Idle state tracking
    var idleStateManager: IdleStateManager?
    // Decision timer task
    private var decisionTimer: Task<Void, Error>?
    // Ensure initial trigger only runs once when both models have finished loading
    private var didTriggerInitialDecision: Bool = false

    private let manager = ModelManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load persisted chat messages
        loadPersistedChat()
        
        // Initialize system prompt from manager
        chatSystemPrompt = SystemPromptManager.shared.getSystemPrompt()

        // Set up idle state monitoring first - MUST happen before other task initialization
        setupIdleStateMonitoring()
        
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
                    // Make sure idle state manager knows audio is playing
                    self.idleStateManager?.updateState(.audioPlaying, active: true)
                } else {
                    // Audio stopped
                    self.isPlaying = false
                    // Make sure idle state manager knows audio stopped
                    self.idleStateManager?.updateState(.audioPlaying, active: false)
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
    
    // Cancel the decision loop when view model is deallocated
    deinit {
        decisionLoopTask?.cancel()
    }

    // Loop that rolls for a decision-response action when idle
    private func startDecisionLoop() {
        LoggerService.shared.info("===== STARTING DECISION LOOP =====")
        // Initialize property for the idle state manager if needed
        if idleStateManager == nil {
            LoggerService.shared.info("Decision loop: Idle state manager was nil, setting up now")
            setupIdleStateMonitoring()
        }
        
        // Force a log of the current idle state
        if let manager = idleStateManager {
            let isCurrentlyIdle = manager.isIdle
            let activeStatesDesc = manager.activeStates.isEmpty ? "none" : manager.activeStates.map { $0.description }.joined(separator: ", ")
            LoggerService.shared.info("Decision loop starting - Is idle: \(isCurrentlyIdle), Active states: \(activeStatesDesc)")
        } else {
            LoggerService.shared.error("Decision loop: Failed to initialize idle state manager")
        }
        
        // Start the improved decision system
        startImprovedDecisionSystem()
    }
    
    // MARK: - IdleStateManager
    
    /// States that indicate the system is busy and not idle
    enum ActivityState {
        case generating  // LLM is generating
        case userTyping  // User is typing in the input field
        case audioPlaying // Kokoro is playing audio
        case scrolling   // User is scrolling the chat
        
        /// User-friendly description of the state
        var description: String {
            switch self {
            case .generating: return "generating"
            case .userTyping: return "user typing"
            case .audioPlaying: return "audio playing"
            case .scrolling: return "scrolling"
            }
        }
    }
    
    /// Idle timer state manager
    class IdleStateManager {
        /// Current idle time in seconds
        private(set) var idleTime: TimeInterval = 0
        
        /// Last time the system transitioned to idle state
        private var lastIdleStartTime: Date? = Date()
        
        /// Current activity states preventing idle
        private(set) var activeStates: Set<ActivityState> = []
        
        /// Whether the system is currently idle
        var isIdle: Bool { activeStates.isEmpty }
        
        init() {
            // Start with idle time tracking immediately if no activity states are present
            if activeStates.isEmpty {
                lastIdleStartTime = Date()
            }
        }
        
        /// Updates the state manager with a new activity state
        /// - Parameters:
        ///   - state: The activity state to update
        ///   - active: Whether the state is active or inactive
        /// - Returns: True if this caused a transition between idle/active state
        @discardableResult
        func updateState(_ state: ActivityState, active: Bool) -> Bool {
            let wasIdle = isIdle
            
            if active {
                // Adding an active state
                activeStates.insert(state)
                if wasIdle {
                    // Transitioning from idle to active - calculate total idle time so far
                    if let startTime = lastIdleStartTime {
                        idleTime = Date().timeIntervalSince(startTime)
                    }
                    lastIdleStartTime = nil
                    LoggerService.shared.debug("IdleStateManager: Transitioning to active state due to: \(state.description)")
                    return true
                }
            } else {
                // Removing an active state
                activeStates.remove(state)
                if !wasIdle && isIdle {
                    // Transitioning from active to idle - start tracking idle time
                    lastIdleStartTime = Date()
                    LoggerService.shared.debug("IdleStateManager: Transitioning to idle state, removed: \(state.description)")
                    return true
                }
            }
            
            return false
        }
        
        /// Calculates the current idle time
        /// - Returns: Time in seconds the system has been idle, or 0 if not idle
        func getCurrentIdleTime() -> TimeInterval {
            guard isIdle else {
                // Not idle, so no idle time
                return 0
            }
            
            guard let startTime = lastIdleStartTime else {
                lastIdleStartTime = Date() 
                return 0
            }
            
            let currentIdleTime = Date().timeIntervalSince(startTime)
            LoggerService.shared.debug("IdleStateManager: Current idle time: \(currentIdleTime)s")
            return currentIdleTime
        }
        
        /// Reset the idle timer state
        func reset() {
            idleTime = 0
            if isIdle {
                lastIdleStartTime = Date()
                LoggerService.shared.debug("IdleStateManager: Reset while idle - starting new timer")
            } else {
                lastIdleStartTime = nil
                LoggerService.shared.debug("IdleStateManager: Reset while active - clearing timer")
            }
        }
    }
    
    /// Start monitoring system idle state
    func setupIdleStateMonitoring() {
        LoggerService.shared.info("===== SETTING UP IDLE STATE MONITORING =====")
        
        // Create and store the idle state manager
        let manager = IdleStateManager()
        
        // Initialize with current activity states
        let isTypingActive = !inputText.isEmpty
        let isGeneratingActive = isGenerating 
        let isPlayingActive = isPlaying || (KokoroEngine.sharedInstance.playbackState != .idle)
        
        LoggerService.shared.info("IdleStateMonitoring: Initial state - typing: \(isTypingActive), generating: \(isGeneratingActive), audio: \(isPlayingActive)")
        
        // Set initial states
        manager.updateState(.generating, active: isGeneratingActive)
        manager.updateState(.userTyping, active: isTypingActive)
        manager.updateState(.audioPlaying, active: isPlayingActive)
        
        // Store the manager
        idleStateManager = manager
        
        // Monitor LLM generation state
        $isGenerating
            .removeDuplicates()
            .sink { [weak self] isGenerating in
                LoggerService.shared.debug("State change: Generation state -> \(isGenerating)")
                self?.idleStateManager?.updateState(.generating, active: isGenerating)
                self?.updateDecisionTimer()
            }
            .store(in: &cancellables)
        
        // Monitor user typing state
        $inputText
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] isTyping in
                LoggerService.shared.debug("State change: User typing -> \(isTyping)")
                self?.idleStateManager?.updateState(.userTyping, active: isTyping)
                self?.updateDecisionTimer()
            }
            .store(in: &cancellables)
        
        // Monitor audio playback state
        KokoroEngine.playbackBus.publisher
            .map { $0 != .idle }
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                LoggerService.shared.debug("State change: Audio playback -> \(isPlaying)")
                self?.idleStateManager?.updateState(.audioPlaying, active: isPlaying)
                self?.updateDecisionTimer()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .chatScrollingStateChanged)
            .map { ($0.userInfo?["isScrolling"] as? Bool) ?? false }
            .sink { [weak self] isScrolling in
                self?.idleStateManager?.updateState(.scrolling, active: isScrolling)
                self?.updateDecisionTimer()
            }
            .store(in: &cancellables)
        
        // Log initial idle state
        LoggerService.shared.debug("IdleStateMonitoring: Setup complete - is idle: \(manager.isIdle)")
    }
    
    // MARK: - Adaptive Decision System
    
    /// Start the improved decision loop system
    func startImprovedDecisionSystem() {
        // Cancel any existing decision tasks and timers
        decisionLoopTask?.cancel()
        decisionTimer?.cancel()
        
        // Make sure idle state monitoring is active
        if idleStateManager == nil {
            setupIdleStateMonitoring()
            LoggerService.shared.debug("Decision system: Setting up idle state monitoring during system start")
        }
        
        // Create action group with default settings
        let group = DecisionResponseActionGroup(
            viewModel: self,
            initialProbability: decisionProbability,
            probabilityIncrement: probabilityIncrement
        )
        
        // Subscribe for TTS playback
        group.subscribeToProgress(for: DecisionResponseActionGroup.ActionId.response) { [weak self] token in
            Task { @MainActor in
                if self?.ttsEnabled == true && token.count > 1 {
                    try Task.checkCancellation()
                    await KokoroEngine.sharedInstance.play(token)
                }
            }
        }
        
        // Store reference
        decisionResponseGroup = group
        
        // Set initial decision timer
        resetDecisionTimer()
        
        // Start the decision loop task
        decisionLoopTask = Task { [weak self] in
            guard let self = self else { return }
            LoggerService.shared.debug("Decision system: Starting decision loop")
            
            // Continue while task is not cancelled
            while !Task.isCancelled {
                // Wait for the timer to fire or be cancelled
                if let timer = self.decisionTimer {
                    do {
                        try await timer.value
                        LoggerService.shared.debug("Decision system: Timer fired normally")
                    } catch {
                        // Timer was cancelled - we'll restart with new timing if needed
                        LoggerService.shared.debug("Decision system: Timer was cancelled")
                        continue
                    }
                } else {
                    // No timer set, use a short delay and then continue
                    LoggerService.shared.debug("Decision system: No timer found, creating new timer")
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    resetDecisionTimer()
                    continue
                }
                
                // Check if we have a valid idle state manager
                guard let manager = self.idleStateManager else {
                    LoggerService.shared.debug("Decision system: No idle state manager, creating one")
                    // Initialize it if needed
                    self.setupIdleStateMonitoring()
                    self.resetDecisionTimer()
                    continue
                }
                
                // Execute decision logic only if we're actually idle
                if manager.isIdle {
                    // Double-check all active states directly before proceeding
                    let forceCheckGenerating = isGenerating
                    let forceCheckTyping = !inputText.isEmpty
                    let forceCheckAudio = isPlaying || (KokoroEngine.sharedInstance.playbackState != .idle)
                    
                    if forceCheckGenerating || forceCheckTyping || forceCheckAudio {
                        LoggerService.shared.warning("Decision system safety check - System reported idle but is actually active! Gen=\(forceCheckGenerating), Type=\(forceCheckTyping), Audio=\(forceCheckAudio)")
                        
                        // Fix the state tracking
                        manager.updateState(.generating, active: forceCheckGenerating)
                        manager.updateState(.userTyping, active: forceCheckTyping)
                        manager.updateState(.audioPlaying, active: forceCheckAudio)
                        
                        // Skip this decision check
                        self.scheduleNextDecisionCheck()
                        continue
                    }
                    
                    let currentIdleTime = manager.getCurrentIdleTime()
                    let lastMsg = self.history.last ?? Message(role: .assistant, category: .chat, content: "", date: Date())
                    
                    // Calculate dynamic probability based on idle time
                    let adaptedProbability = self.calculateDynamicProbability(idleTime: currentIdleTime)
                    
                    // Log the decision attempt
                    LoggerService.shared.debug("Decision check - Idle time: \(Int(currentIdleTime))s, Probability: \(adaptedProbability)%")
                    
                    // Make the decision roll with dynamic probability
                    let shouldRespond = Double.random(in: 0..<100) < adaptedProbability
                    
                    if shouldRespond {
                        LoggerService.shared.info("Decision triggered after \(Int(currentIdleTime))s idle")
                        
                        // Execute the decision response
                        await self.decisionResponseGroup?.execute(with: lastMsg)
                        
                        // Reset the decision timer after firing
                        self.resetDecisionTimer()
                    } else {
                        // Schedule next check
                        self.scheduleNextDecisionCheck()
                    }
                } else {
                    // System not idle during check
                    let activeStatesDesc = manager.activeStates.map { $0.description }.joined(separator: ", ")
                    LoggerService.shared.debug("Decision check skipped - System active: \(activeStatesDesc)")
                    self.scheduleNextDecisionCheck()
                }
            }
            
            LoggerService.shared.debug("Decision system: Task cancelled, shutting down decision loop")
        }
    }
    
    /// Calculate an adaptive probability based on idle time
    /// - Parameter idleTime: Current system idle time in seconds
    /// - Returns: Adjusted probability percentage (0-100)
    private func calculateDynamicProbability(idleTime: TimeInterval) -> Double {
        // Base values
        let baseProb = decisionProbability
        let maxProb = 95.0
        
        // Calculate idle time brackets
        let shortIdleThreshold = decisionInterval * 1.0  // Standard interval
        let mediumIdleThreshold = decisionInterval * 3.0 // 3x standard interval
        let longIdleThreshold = decisionInterval * 6.0   // 6x standard interval
        
        // Sigmoid-like scaling function for more natural probability growth
        // - Starts slow, accelerates in the middle, then levels off
        if idleTime < shortIdleThreshold {
            // Starting phase: linear growth from base
            return baseProb
        } else if idleTime < mediumIdleThreshold {
            // Acceleration phase: faster growth
            let progress = (idleTime - shortIdleThreshold) / (mediumIdleThreshold - shortIdleThreshold)
            let quadratic = progress * progress // Quadratic growth
            return baseProb + (maxProb - baseProb) * 0.5 * quadratic
        } else if idleTime < longIdleThreshold {
            // High probability phase
            let progress = (idleTime - mediumIdleThreshold) / (longIdleThreshold - mediumIdleThreshold)
            let invQuadratic = 1 - (1 - progress) * (1 - progress) // Inverse quadratic for smooth approach
            return baseProb + (maxProb - baseProb) * (0.5 + 0.5 * invQuadratic)
        } else {
            // Maximum probability after long idle
            return maxProb
        }
    }
    
    /// Schedule the next decision check based on current state
    private func scheduleNextDecisionCheck() {
        let nextCheckInterval: TimeInterval
        
        if let manager = idleStateManager, manager.isIdle {
            // System is idle - schedule based on idle time
            let currentIdleTime = manager.getCurrentIdleTime()
            
            // Adaptive check interval - check more frequently the longer we're idle
            if currentIdleTime < decisionInterval {
                // For very short idle periods, use a time proportional to the remaining interval
                nextCheckInterval = max(1.0, decisionInterval - currentIdleTime)
            } else if currentIdleTime < decisionInterval * 3 {
                // More frequent checks after initial wait
                nextCheckInterval = max(decisionInterval * 0.5, 2.0)
            } else {
                // Very frequent checks after long idle
                nextCheckInterval = max(decisionInterval * 0.25, 1.0)
            }
            
            LoggerService.shared.debug("Decision system: Next check in \(nextCheckInterval)s (idle time: \(currentIdleTime)s)")
        } else {
            // System is active - use standard interval
            nextCheckInterval = decisionInterval
            LoggerService.shared.debug("Decision system: System active, next check in \(nextCheckInterval)s")
        }
        
        resetDecisionTimer(interval: nextCheckInterval)
    }
    
    /// Reset the decision timer with an optional custom interval
    private func resetDecisionTimer(interval: TimeInterval? = nil) {
        // Cancel existing timer if any
        decisionTimer?.cancel()
        
        // Calculate interval to use
        let useInterval = interval ?? decisionInterval
        let nanoseconds = UInt64(max(1.0, useInterval) * 1_000_000_000) // Ensure at least 1 second
        
        // Create new timer task
        decisionTimer = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
                // Let it complete normally
            } catch {
                // Handle cancellation or other errors
                LoggerService.shared.debug("Decision timer: Timer cancelled or error")
                throw error // Re-throw to propagate to caller
            }
        }
        
        LoggerService.shared.debug("Decision timer: New timer created for \(useInterval)s")
    }
    
    /// Update the decision timer in response to system state changes
    private func updateDecisionTimer() {
        guard let manager = idleStateManager else {
            LoggerService.shared.debug("Decision timer: No idle state manager available")
            return
        }
        
        if manager.isIdle {
            // System just became idle - start/update the timer
            let currentIdleTime = manager.getCurrentIdleTime()
            
            if decisionTimer == nil {
                // No timer running, start a new one
                resetDecisionTimer()
                LoggerService.shared.debug("Decision timer: System idle, starting decision timer (idle time: \(currentIdleTime)s)")
            } else {
                // Timer already running - leave it alone since it will handle the next check
                LoggerService.shared.debug("Decision timer: System still idle, timer already running (idle time: \(currentIdleTime)s)")
            }
        } else {
            // System is busy - reset the timer to standard interval
            let activeStatesDesc = manager.activeStates.map { $0.description }.joined(separator: ", ")
            LoggerService.shared.debug("Decision timer: System active (\(activeStatesDesc)), resetting decision timer")
            resetDecisionTimer()
        }
    }
}
