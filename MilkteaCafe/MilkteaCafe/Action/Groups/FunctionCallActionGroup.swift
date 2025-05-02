import Foundation

/// ActionGroup implementation for function calling
/// Processes user input through function calling, 
/// then runs chat and summary actions
class FunctionCallActionGroup: ActionGroup {
    // Storage for final results
    private(set) var results: [String: Any] = [:]
    
    // Progress handlers for different action types
    private var progressHandlers: [String: [(String) -> Void]] = [:]
    
    // Reference to view model (weak to avoid cycles)
    private weak var viewModel: ChatViewModel?
    
    // FunctionCall instance
    private let functionCall: FunctionCall
    
    // Identifiers for our actions
    enum ActionId {
        static let functionCall = "functionCall"
        static let tone = "tone"
        static let chat = "chat"
        static let summary = "summary"
    }
    
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        
        // Create and configure FunctionCall
        self.functionCall = FunctionCall()
            .addStandardFunctions()
            .build()
        
        // Register standard functions
        self.functionCall.registerStandardFunctions()
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
    func execute(with initialMessage: Message) async {
        // Start with function call analysis
        await runFunctionCallAction(initialMessage: initialMessage)
    }
    
    // MARK: - Individual Action Execution Methods
    
    private func runFunctionCallAction(initialMessage: Message) async {

        // Store the initial message for potential use in chained functions
        let savedInitialMessage = initialMessage
        
        // Get system prompt from the FunctionCall instance
        let systemPrompt = functionCall.getSystemPrompt()
        
        let functionAction = AnyAction(
            systemPrompt: systemPrompt,
            messages: [],
            message: Message(role: .user, content: initialMessage.content),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FunctionCallFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of function call progress
                self?.notifyProgress(actionId: ActionId.functionCall, token: token)
            },
            runCode: { [weak self] response in
                guard let self = self else { return (false, response) }
                
                // Process the response to execute the function
                return self.functionCall.processResponse(response, initialMessage: savedInitialMessage)
            },
            postAction: { [weak self] result in
                guard let self = self else { return }
                
                // Store result
                if let resultDict = result as? [String: Any] {
                    self.results[ActionId.functionCall] = resultDict
                    
                    // Extract function name and result
                    let functionName = resultDict["functionCalled"] as? String ?? "unknown"
                    let functionResult = resultDict["result"] as? Bool ?? false
                    
                    LoggerService.shared.info("Function \(functionName) executed with result: \(functionResult)")
                    
                    // Proceed to next action with modified message if needed
                    var modifiedMessage = initialMessage
                    
                    // If function was successful, add context for the chat action
                    if functionResult {
                        var additionalContext = ""
                        
                        // Add specific context based on which function was called
                        switch functionName {
                        case "changeSystemPrompt":
                            additionalContext = "\n\nThe system prompt was updated successfully."
                        case "rememberName":
                            additionalContext = "\n\nThe assistant has remembered a name."
                        case "enableVoiceSupport":
                            let enabled = resultDict["result"] as? Bool ?? false
                            additionalContext = "\n\nVoice support has been \(enabled ? "enabled" : "disabled")."
                        case "noOperation":
                            // No additional context needed for no-op
                            break
                        default:
                            // For any custom functions
                            additionalContext = "\n\nThe function '\(functionName)' was executed successfully."
                        }
                        
                        // Only modify message if we have additional context
                        if !additionalContext.isEmpty {
                            modifiedMessage = Message(
                                role: .user,
                                category: initialMessage.category,
                                content: initialMessage.content + additionalContext,
                                date: initialMessage.timestamp
                            )
                        }
                    }
                    
                    // Proceed to tone action instead of directly to chat
                    Task {
                        await self.runToneAction(initialMessage: modifiedMessage, functionResult: resultDict)
                    }
                } else {
                    // Function call failed or invalid response
                    LoggerService.shared.warning("Invalid function call result")
                    Task {
                        await self.runToneAction(initialMessage: initialMessage, functionResult: nil)
                    }
                }
            }
        )
        
        await ActionRunner.shared.run(functionAction)
    }
    
    private func runToneAction(initialMessage: Message, functionResult: [String: Any]?) async {
        guard let viewModel = viewModel else { return }
        
        let history = MessageStore.shared.getRecentMessages(category: .summary, limit: 1).first?.content ?? ""
        // Get the thinking system prompt and template
        let systemPrompt = await MainActor.run {
            return viewModel.thinkingSystemPrompt
        }
        
        let promptTemplate = await MainActor.run {
            return viewModel.thinkingPromptTemplate
        }
        
        let content = promptTemplate.replacingOccurrences(of: "{prompt}", with: history + "\n\nUser: \(initialMessage.content)")
        
        let toneAction = AnyAction(
            systemPrompt: systemPrompt,
            messages: [],
            message: Message(role: .user, content: content),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of tone progress
                self?.notifyProgress(actionId: ActionId.tone, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { result in
            
                let toneAnalysis = (result as? String) ?? ""
                
                // Store result
                self.results[ActionId.tone] = toneAnalysis
                
                // Update UI on the main actor
                Task { @MainActor in
                    self.viewModel?.thinkingTone = toneAnalysis
                }
                
                // Proceed to chat action
                Task {
                    await self.runChatAction(initialMessage: initialMessage, functionResult: functionResult, toneAnalysis: toneAnalysis)
                }
            }
        )
        
        await ActionRunner.shared.run(toneAction)
    }
    
    private func runChatAction(initialMessage: Message, functionResult: [String: Any]?, toneAnalysis: String) async {
        guard let viewModel = viewModel else { return }
        
        // Get history and system prompt on the main actor
        let history = await MainActor.run {
            return MessageStore.shared.getRecentMessages(category: .chat)
        }
        
        let systemPrompt = await MainActor.run {
            return viewModel.chatSystemPrompt
        }
        
        let usesTTS = await MainActor.run {
            return viewModel.ttsEnabled
        }
        
        // Get chat prompt template
        let promptTemplate = await MainActor.run {
            return viewModel.chatPromptTemplate
        }
        
        // Format the final prompt with tone information if available
        var userMessage = initialMessage
        if !toneAnalysis.isEmpty {
            // Format the prompt template with tone
            let formattedPrompt = promptTemplate
                .replacingOccurrences(of: "{tone}", with: toneAnalysis)
                .replacingOccurrences(of: "{prompt}", with: initialMessage.content)
            
            // Create a new message with the formatted content
            userMessage = Message(
                role: .user,
                category: initialMessage.category,
                content: formattedPrompt,
                date: initialMessage.timestamp
            )
        }
        
        let chatAction = AnyAction(
            systemPrompt: systemPrompt,
            messages: history,
            message: userMessage,
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
            message: Message(role: .user, content: summaryPrompt),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of summary progress
                self?.notifyProgress(actionId: ActionId.summary, token: token)
            },
            runCode: { response in (false, response) },
            postAction: { [weak self] result in
                guard let self = self else { return }
                
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
