import Foundation

/// A specialized action for local ML processing that doesn't use the LLM.
/// This is used for lightweight classification and prediction tasks.
struct LocalMLAction: Action {
    // Standard Action protocol conformance
    var messages: [Message] { [] }
    let message: Message
    let systemPrompt: String = ""
    let clearKVCache: Bool = false
    let modelType: ModelType = .thinking // Keep as thinking type for execution flow
    
    // Custom properties for ML execution
    let processDataClosure: (String) -> Any
    private let postActionClosure: (Any) -> Void
    
    init(
        inputMessage: Message,
        process: @escaping (String) -> Any,
        postAction: @escaping (Any) -> Void
    ) {
        self.message = inputMessage
        self.processDataClosure = process
        self.postActionClosure = postAction
    }
    
    // Preparation does nothing for LocalMLAction since we don't need dependencies
    func prepareForExecution(with dependencies: [String: Any]) async -> Bool {
        return true
    }
    
    // The runCode method executes the ML model directly
    func runCode(on response: String) -> (didRun: Bool, result: Any) {
        // Process the message content with the ML model
        let result = processDataClosure(message.content)
        return (true, result)
    }
    
    // Pass the result to the post action
    func postAction(_ result: Any) {
        DispatchQueue.main.async {
            self.postActionClosure(result)
        }
    }
}

/// Extension of ActionRunner to handle LocalMLAction specifically
extension ActionRunner {
    /// Execute a LocalMLAction directly without using the LLM
    func runLocalML(_ action: LocalMLAction) async {
        // Skip LLM processing entirely
        let result = action.processDataClosure(action.message.content)
        action.postAction(result)
    }
    
    /// Override run method to check for LocalMLAction
    func run(action: Action) async {
        if let mlAction = action as? LocalMLAction {
            // Use specialized execution for ML actions
            await runLocalML(mlAction)
        } else {
            // Use standard execution for normal actions
            await run(action)
        }
    }
}
