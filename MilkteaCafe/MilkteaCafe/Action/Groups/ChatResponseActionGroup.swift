import LowkeyTeaLLM

class ChatResponseActionGroup: ActionGroup {
    // Storage for final results
    private(set) var results: [String: Any] = [:]
    
    // Progress handlers for different action types
    private var progressHandlers: [String: [(String) -> Void]] = [:]
    
    // Reference to view model (weak to avoid cycles)
    private weak var viewModel: ChatViewModel?
    
    // Identifiers for our actions
    enum ActionId {
        static let tone = "tone"
        static let chat = "chat"
        static let summary = "summary"
    }
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
    }
    
    /// Register a progress handler for a specific action type
    func subscribeToProgress(for actionId: String, handler: @escaping (String) -> Void) {
        if progressHandlers[actionId] == nil {
            progressHandlers[actionId] = []
        }
        progressHandlers[actionId]?.append(handler)
    }
    
    /// Notify all subscribers of progress for a specific action
    private func notifyProgress(actionId: String, token: String) {
        progressHandlers[actionId]?.forEach { handler in
            handler(token)
        }
    }
    
    /// Execute the full chain of actions
    func execute(with initialMessage: LlamaMessage) async {
        // Start with tone analysis
        await runToneAction(initialMessage: initialMessage)
    }
    
    // MARK: - Individual Action Execution Methods
    
    private func runToneAction(initialMessage: LlamaMessage) async {
        guard let viewModel = viewModel else { return }
        
        
        // Get history on the main actor
        let history = await MainActor.run {
            return MessageStore.shared.getRecentMessages(category: .summary, limit: 1)
        }.first?.content ?? "This is the first message."
        
        let content = "The conversation so far: \(history).\n\nUser Prompt: \(initialMessage.content)"
        // Get prompt template on the main actor
        let tonePrompt = await MainActor.run {
            viewModel.thinkingPromptTemplate
                .replacingOccurrences(of: "{prompt}", with: content)
        }
        // Get system prompt on the main actor
        let systemPrompt = await MainActor.run {
            return viewModel.thinkingSystemPrompt
        }
        
        
        let toneAction = AnyAction(
            systemPrompt: systemPrompt,
            messages: [],
            message: LlamaMessage(role: .user, content: tonePrompt),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of tone progress
                self?.notifyProgress(actionId: ActionId.tone, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { result in
                let tone = (result as? String) ?? ""
                
                // Store result
                self.results[ActionId.tone] = tone
                
                // Update UI on the main actor
                Task { @MainActor in
                    self.viewModel?.thinkingTone = tone
                }
                
                // Proceed to next action
                Task {
                    await self.runChatAction(initialMessage: initialMessage, tone: tone)
                }
            }
        )
        
        await ActionRunner.shared.run(toneAction)
    }
    
    private func runChatAction(initialMessage: LlamaMessage, tone: String) async {
        guard let viewModel = viewModel else { return }
        
        // Get template and create content on the main actor
        let chatContent = await MainActor.run {
            return viewModel.chatPromptTemplate
                .replacingOccurrences(of: "{tone}", with: tone)
                .replacingOccurrences(of: "{prompt}", with: initialMessage.content)
        }
        
        // Get history and system prompt on the main actor
        let history = await MainActor.run {
            return Array(viewModel.history.dropLast())
        }
        
        let systemPrompt = await MainActor.run {
            return viewModel.chatSystemPrompt
        }
        
        let usesTTS = await MainActor.run {
            return viewModel.ttsEnabled
        }
        
        let chatAction = AnyAction(
            systemPrompt: systemPrompt,
            messages: history,
            message: LlamaMessage(role: .user, content: chatContent),
            clearKVCache: false,
            modelType: .chat,
            tokenFilter: usesTTS ? SentenceFilter() : PassThroughFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of chat progress
                self?.notifyProgress(actionId: ActionId.chat, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { result in
                let reply = (result as? String) ?? ""
                
                // Store result
                self.results[ActionId.chat] = reply
                // Persist the final assistant response
                let assistantMsg = Message(role: .assistant, category: .chat, content: reply)
                MessageStore.shared.addMessage(assistantMsg)

                // Proceed to next action after a brief delay to ensure history is updated
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                    await self.runSummaryAction()
                }
            }
        )
        
        await ActionRunner.shared.run(chatAction)
    }
    
    private func runSummaryAction() async {
        guard let viewModel = viewModel else { return }
        
        // Get history on the main actor
        let history = await MainActor.run {
            return viewModel.history
        }
        
        // Format messages
        let content = history.map { "The \($0.role.rawValue) said: \($0.content)\n" }.joined()
        let summaryPrompt = "Summarize the following conversation in the form of 3 or less sentences for the user, and 3 or less for the assistant: \n\n\(content)"
        
        let summaryAction = AnyAction(
            systemPrompt: "You are an AI agent who summarizes conversations. Focus on capturing the key details of the conversation.",
            messages: [],
            message: LlamaMessage(role: .user, content: summaryPrompt),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of summary progress
                self?.notifyProgress(actionId: ActionId.summary, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { result in
                let summary = (result as? String) ?? ""
                
                // Store result
                self.results[ActionId.summary] = summary
                
                // Update UI and persist summary on the main actor
                Task { @MainActor in
                    self.viewModel?.thinkingOutput = summary
                    self.viewModel?.isGenerating = false
                    // Persist the summary message
                    let summaryMsg = Message(role: .assistant, category: .summary, content: summary)
                    MessageStore.shared.addMessage(summaryMsg)
                }
            }
        )
        
        await ActionRunner.shared.run(summaryAction)
    }
}
