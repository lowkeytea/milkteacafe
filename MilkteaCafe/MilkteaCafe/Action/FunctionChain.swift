import Foundation
import LowkeyTeaLLM

/// Class for managing sequences of function calls
class FunctionChain {
    /// Definition of a function step in a chain
    struct ChainStep {
        /// Unique identifier for this step
        let id: String
        
        /// System prompt to use for this step
        let systemPrompt: String
        
        /// Message generator for this step
        let messageGenerator: (_ previousResults: [String: Any], _ initialMessage: LlamaMessage) -> LlamaMessage
        
        /// Result handler for this step
        let resultHandler: (_ result: Any, _ previousResults: [String: Any]) -> [String: Any]
        
        /// Whether to clear KV cache for this step
        let clearKVCache: Bool
        
        /// Optional condition to decide if this step should be executed
        let condition: ((_ previousResults: [String: Any]) -> Bool)?
    }
    
    /// The steps in this chain
    private var steps: [ChainStep] = []
    
    /// The results from each step
    private var stepResults: [String: Any] = [:]
    
    /// The initial message that triggered the chain
    private var initialMessage: LlamaMessage?
    
    /// The completion handler to call when the chain is complete
    private var completionHandler: ((_ results: [String: Any]) -> Void)?
    
    /// Initialize a new function chain
    init() {}
    
    /// Add a step to the chain
    @discardableResult
    func addStep(_ step: ChainStep) -> FunctionChain {
        steps.append(step)
        return self
    }
    
    /// Execute the chain with an initial message
    func execute(with message: LlamaMessage, completion: @escaping (_ results: [String: Any]) -> Void) async {
        self.initialMessage = message
        self.completionHandler = completion
        self.stepResults = [:]
        
        // Start with the first step
        await executeNextStep(currentIndex: 0)
    }
    
    /// Execute the next step in the chain
    private func executeNextStep(currentIndex: Int) async {
        // Check if we've reached the end of the chain
        guard currentIndex < steps.count else {
            // Chain is complete, call completion handler
            completionHandler?(stepResults)
            return
        }
        
        // Get the current step
        let step = steps[currentIndex]
        
        // Check if this step should be executed
        if let condition = step.condition, !condition(stepResults) {
            // Skip this step and proceed to the next one
            await executeNextStep(currentIndex: currentIndex + 1)
            return
        }
        
        // Generate message for this step
        guard let initialMessage = initialMessage else {
            LoggerService.shared.error("FunctionChain: No initial message")
            completionHandler?(stepResults)
            return
        }
        
        let message = step.messageGenerator(stepResults, initialMessage)
        
        // Create action for this step
        let action = AnyAction(
            systemPrompt: step.systemPrompt,
            messages: [],
            message: message,
            clearKVCache: step.clearKVCache,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: nil,
            runCode: { response in
                // Default is to just pass through the response
                return (false, response)
            },
            postAction: { [weak self] result in
                guard let self = self else { return }
                
                // Process the result
                let updatedResults = step.resultHandler(result, self.stepResults)
                
                // Update the step results
                self.stepResults = updatedResults
                
                // Store the result with the step ID
                self.stepResults[step.id] = result
                
                // Move to the next step
                Task {
                    await self.executeNextStep(currentIndex: currentIndex + 1)
                }
            }
        )
        
        // Execute the action
        await ActionRunner.shared.run(action)
    }
}
