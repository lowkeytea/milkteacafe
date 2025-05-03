import Foundation

/// ActionGroup implementation for function calling
/// Processes user input through function calling, 
/// then runs chat and summary actions
class FunctionCallActionGroup: ActionGroup {
    // Configuration for summary action
    static let messagesPerSummary = 5  // Run summary every N user messages
    // Storage for final results
    private(set) var results: [String: Any] = [:]
    
    // Progress handlers for different action types
    private var progressHandlers: [String: [(String) -> Void]] = [:]
    
    // Reference to view model (weak to avoid cycles)
    weak var viewModel: ChatViewModel?
    
    // FunctionCall instance
    let functionCall: FunctionCall
    
    // Prompt templates and system prompts
    let thinkingSystemPrompt: String
    let thinkingPromptTemplate: String
    let chatSystemPrompt: String
    let chatPromptTemplate: String
    
    // Identifiers for our actions
    enum ActionId {
        static let functionCall = "functionCall"
        static let tone = "tone"
        static let chat = "chat"
        static let summary = "summary"
    }
    
    @MainActor
    init(viewModel: ChatViewModel) {
        self.viewModel = viewModel
        
        // Get prompt values from view model (needs MainActor to access these properties)
        self.thinkingSystemPrompt = viewModel.thinkingSystemPrompt
        self.thinkingPromptTemplate = viewModel.thinkingPromptTemplate
        self.chatSystemPrompt = viewModel.chatSystemPrompt
        self.chatPromptTemplate = viewModel.chatPromptTemplate
        
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
    func notifyProgress(actionId: String, token: String) {
        progressHandlers[actionId]?.forEach { handler in
            handler(token)
        }
    }
    
    /// Execute the full chain of actions
    @MainActor
    func execute(with initialMessage: Message) async {
        // Create action queue for dependency-based execution
        let queue = ActionQueue()
        
        // Define a shared action result dictionary
        var actionResults: [String: Any] = [:]
        
        // Create action nodes with their dependencies
        
        // 1. Tone Analysis Action (no dependencies)
        let toneAction = createToneAction(initialMessage: initialMessage) { result in
            actionResults[ActionId.tone] = result
        }
        let toneNode = ActionNode(id: ActionId.tone, action: toneAction)
        
        // 2. Function Call Action (depends on tone)
        let functionAction = createFunctionCallAction(initialMessage: initialMessage) { result in
            actionResults[ActionId.functionCall] = result
        }
        let functionNode = ActionNode(
            id: ActionId.functionCall, 
            action: functionAction,
            dependencies: [ActionId.tone],
            completion: { result in
                LoggerService.shared.info("FunctionCallActionGroup: Function call action completed with result type: \(type(of: result))")
                // Store the result in our shared results dictionary
                actionResults[ActionId.functionCall] = result
            }
        )
        
        // 3. Chat Action (depends on tone, but not on function call completion)
        // With lazy preparation, we don't need to pass the queue anymore since
        // dependencies are injected just before execution
        let chatAction = await createChatAction(
            initialMessage: initialMessage,
            toneId: ActionId.tone
        ) { result in
            actionResults[ActionId.chat] = result
        }
        
        let chatNode = ActionNode(
            id: ActionId.chat, 
            action: chatAction,
            dependencies: [ActionId.tone],
            completion: { result in
                let reply = (result as? String) ?? ""
                
                // Store in message store directly
                let assistantMsg = Message(role: .assistant, category: .chat, content: reply)
                MessageStore.shared.addMessage(assistantMsg)
            }
        )
        
        // 4. Summary Action (run only every N messages)
        var nodesToRun = [toneNode, functionNode, chatNode]
        
        // Check if we should run summary based on message count
        let userMessageCount = MessageStore.shared.getUserMessageCount()
        let shouldRunSummary = userMessageCount % Self.messagesPerSummary == 0
        
        // Only create and add the summary node if we should run it
        if shouldRunSummary {
            LoggerService.shared.info("FunctionCallActionGroup: Running summary action (message count: \(userMessageCount))")
            
            let summaryAction = createSummaryAction { result in
                actionResults[ActionId.summary] = result
                
                // Update UI and persist on completion
                Task { @MainActor in
                    self.viewModel?.thinkingOutput = (result as? String) ?? ""
                    self.viewModel?.isGenerating = false
                    
                    // Persist the summary message
                    let summary = (result as? String) ?? ""
                    let summaryMsg = Message(role: .assistant, category: .summary, content: summary)
                    MessageStore.shared.addMessage(summaryMsg)
                }
            }
            let summaryNode = ActionNode(
                id: ActionId.summary, 
                action: summaryAction,
                dependencies: [ActionId.chat, ActionId.functionCall]
            )
            
            nodesToRun.append(summaryNode)
        } else {
            #if DEBUG
            LoggerService.shared.debug("FunctionCallActionGroup: Skipping summary action (message count: \(userMessageCount))")
            #endif
            
            // Still need to handle UI state update when not running summary
            Task { @MainActor in
                // Wait a short time to allow chat to complete
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                self.viewModel?.isGenerating = false
            }
        }
        
        // Add all nodes to the queue
        await queue.enqueueAll(nodesToRun)
        
        // Create a watchdog task that will ensure we don't hang forever
        let watchdogTask = Task {
            do {
                // Wait up to 80 seconds max for queue processing
                try await Task.sleep(nanoseconds: 80_000_000_000)
                LoggerService.shared.warning("FunctionCallActionGroup: Queue processing timed out, forcing cleanup")
                await queue.cleanup()
            } catch {
                // Task was cancelled normally when queue finished
            }
        }
        
        // Wait for all queue processing to complete
        var observationTask: Task<Void, Never>?
        
        await withCheckedContinuation { continuation in
            observationTask = Task {
                // Check every 250ms if any tasks are still running
                while !Task.isCancelled {
                    // Check if all nodes are done
                    let isDone = await queue.allNodesComplete()
                    if isDone {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                
                // Clean up resources
                await queue.cleanup()
                
                // Cancel the watchdog
                watchdogTask.cancel()
                
                // Resume continuation
                continuation.resume()
            }
        }
        
        // Cancel our observation task if it's still running
        observationTask?.cancel()
    }
}
