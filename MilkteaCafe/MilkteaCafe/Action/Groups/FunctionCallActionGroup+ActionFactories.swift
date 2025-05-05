import Foundation
import CoreML

/// Extension containing factory methods for creating actions
extension FunctionCallActionGroup {
    
    /// Creates a tone analysis action using the ML classifier
    func createToneAction(initialMessage: Message, completion: @escaping (Any) -> Void) -> Action {
        guard viewModel != nil else {
            return createEmptyAction(completion: completion)
        }
        
        // Create a LocalMLAction instead of AnyAction to bypass the LLM
        return LocalMLAction(
            inputMessage: Message(role: .user, content: initialMessage.content),
            // Process function executes the ML model directly
            process: { messageContent in
                // Create and use the text classifier
                if let classifier = TextClassifierFactory.createShortLongClassifier(),
                   let result = classifier.classifyShortLong(messageContent) {
                    
                    // Log the classification result
                    LoggerService.shared.info("ML Classification: \(result.label) with confidence \(result.confidence)")
                    
                    // Determine tone guidance based on classification
                    let toneGuidance: String
                    if result.isShort {
                        toneGuidance = "You should reply with a short response."
                    } else {
                        toneGuidance = "You should reply with a long response."
                    }
                    
                    // Include confidence and all predictions in debug mode
                    #if DEBUG
                    let debugInfo = """
                    Classification: \(result.label.uppercased())
                    Confidence: \(Int(result.confidence * 100))%
                    All predictions: \(result.allPredictions)
                    """
                    LoggerService.shared.debug(debugInfo)
                    #endif
                    
                    return toneGuidance
                } else {
                    // Fallback if classifier fails
                    LoggerService.shared.warning("ML Classifier failed, using default tone")
                    return "Reply naturally based on the query length and complexity."
                }
            },
            // Post action function for handling the result
            postAction: { result in
                let toneAnalysis = (result as? String) ?? ""
                
                // Store result for UI on the main actor (needs @MainActor context)
                Task { @MainActor in
                    if let vm = self.viewModel {
                        vm.thinkingTone = toneAnalysis
                    }
                }
                
                // Call completion handler to pass the result to the next action
                completion(toneAnalysis)
                
                // Log the tone analysis to help with debugging
                #if DEBUG
                LoggerService.shared.debug("Tone analysis complete: \(toneAnalysis)")
                #endif
            }
        )
    }
    
    /// Creates a function call action using the lazy approach
    func createFunctionCallAction(initialMessage: Message, completion: @escaping (Any) -> Void) -> Action {
        return AnyAction(
            systemPrompt: "", // Will be prepared during lazy execution
            messages: [],
            message: Message(role: .user, content: ""),
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FunctionCallFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of function call progress
                self?.notifyProgress(actionId: ActionId.functionCall, token: token)
            },
            // Lazy preparation function
            prepare: { [weak self, initialMessage] dependencies -> (Bool, Message?, String?) in
                guard let self = self else {
                    return (false, nil, nil)
                }
                
                // Generate the system prompt just before execution
                let systemPrompt = "\(self.functionCall.getSystemPrompt())\n\nUser Input: \(initialMessage.content)"
                #if DEBUG
                LoggerService.shared.debug("Function call action prepared with system prompt length: \(systemPrompt.count)")
                #endif
                
                // We don't need to modify the message for function calls, just prepare the system prompt
                // Return true, nil message, and new system prompt
                return (true, nil, systemPrompt)
            },
            runCode: { [weak self] response in
                guard let self = self else { return (false, response) }
                
                // Process the response to execute the function
                return self.functionCall.processResponse(response, initialMessage: initialMessage)
            },
            postAction: { result in
                
                if let resultDict = result as? [String: Any] {
                    // Extract function name and result
                    let functionName = resultDict["functionCalled"] as? String ?? "unknown"
                    let functionResult = resultDict["result"] as? Bool ?? false
                    
                    LoggerService.shared.info("Function \(functionName) executed with result: \(functionResult)")
                    
                    // Call completion handler
                    completion(resultDict)
                } else {
                    // Function call failed
                    LoggerService.shared.warning("Invalid function call result")
                    completion(["error": "Invalid function call result"])
                }
            }
        )
    }
    
    /// Creates a chat action using the lazy preparation pattern
    func createChatAction(
        initialMessage: Message, 
        toneId: String,
        completion: @escaping (Any) -> Void
    ) async -> Action {
        guard let viewModel = viewModel else {
            return createEmptyAction(completion: completion)
        }
        
        // Get history directly from message store
        let history = MessageStore.shared.getRecentMessages(category: .chat)
        
        // Get tts setting with proper MainActor context
        let usesTTS = await MainActor.run { viewModel.ttsEnabled }
        
        // Use the group's prompt templates
        let systemPrompt = self.chatSystemPrompt
        
        // Create the action with just the basics - detailed preparation happens later
        return AnyAction(
            systemPrompt: systemPrompt,
            messages: history,
            message: initialMessage, // This will be replaced during preparation
            clearKVCache: false,
            modelType: .chat,
            tokenFilter: usesTTS ? SentenceFilter() : PassThroughFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of chat progress
                self?.notifyProgress(actionId: ActionId.chat, token: token)
            },
            // New lazy preparation closure - only runs right before execution
            prepare: { [weak self, toneId] dependencies -> (Bool, Message?, String?) in
                guard let self = self else {
                    LoggerService.shared.warning("Chat action preparation failed: self is nil")
                    return (false, nil, nil)
                }
                
                // Get tone from dependencies
                var toneAnalysis = ""
                if let toneResult = dependencies[toneId] as? String {
                    toneAnalysis = toneResult
                    #if DEBUG
                    LoggerService.shared.debug("Chat action using tone from dependencies: \(toneAnalysis)")
                    #endif
                } else {
                    // Fallback to viewModel as a safety measure (shouldn't happen in normal operation)
                    toneAnalysis = await MainActor.run { self.viewModel?.thinkingTone ?? "" }
                    LoggerService.shared.warning("Chat action falling back to viewModel for tone - dependency system may not be working properly")
                }
                
                // Format the prompt with tone information
                let formattedPrompt = self.chatPromptTemplate
                    .replacingOccurrences(of: "{tone}", with: toneAnalysis)
                    .replacingOccurrences(of: "{prompt}", with: initialMessage.content)
                
                // Log the formatted prompt to help with debugging
                #if DEBUG
                LoggerService.shared.debug("Chat action formatting prompt with tone:\n\(toneAnalysis)")
                #endif
                
                // Create a new message with the formatted content
                let userMessage = Message(
                    role: .user,
                    category: initialMessage.category,
                    content: formattedPrompt,
                    date: initialMessage.timestamp
                )
                
                // Return success, new message, no change to system prompt
                return (true, userMessage, nil)
            },
        
            runCode: { response in (false, response) },
            postAction: { result in
                let reply = (result as? String) ?? ""
                completion(reply)
            }
        )
    }
    
    /// Creates a summary action using the lazy preparation pattern
    func createSummaryAction(completion: @escaping (Any) -> Void) -> Action {
        guard viewModel != nil else {
            return createEmptyAction(completion: completion)
        }
        
        return AnyAction(
            systemPrompt: "You are an AI agent who summarizes conversations. Focus on capturing the key details of the conversation.",
            messages: [],
            message: Message(role: .user, content: ""), // Will be prepared at execution time
            clearKVCache: true,
            modelType: .thinking,
            tokenFilter: FullResponseFilter(),
            progressHandler: { [weak self] token in
                // Notify subscribers of summary progress
                self?.notifyProgress(actionId: ActionId.summary, token: token)
            },
            // Lazy preparation that can use dependencies
            prepare: { [weak self, chatId = ActionId.chat, functionId = ActionId.functionCall] dependencies -> (Bool, Message?, String?) in
                guard let self = self else {
                    return (false, nil, nil)
                }
                
                // Log the dependencies we're using
                #if DEBUG
                LoggerService.shared.debug("Summary action preparing with dependencies: \(dependencies.keys.joined(separator: ", "))")
                #endif
                
                // Check if the function call completed successfully
                if let functionResult = dependencies[functionId] as? [String: Any] {
                    let functionName = functionResult["functionCalled"] as? String ?? "unknown"
                    #if DEBUG
                    LoggerService.shared.debug("Summary action using function call result from \(functionName)")
                    #endif
                } else {
                    LoggerService.shared.warning("Summary action missing function call result")
                }
                
                // Get chat history directly from message store for now
                // In the future, we could get it from the chat action result
                let history = MessageStore.shared.getRecentMessages(category: .chat)
                
                // Format messages
                let content = history.map { "The \($0.role.rawValue) said: \($0.content)\n" }.joined()
                let summaryPrompt = "Summarize the following conversation in the form of 3 or less sentences for the user, and 3 or less for the assistant: \n\n\(content)"
                
                // Create the message with the content
                let message = Message(role: .user, content: summaryPrompt)
                
                return (true, message, nil)
            },
            runCode: { response in (false, response) },
            postAction: { result in
                let summary = (result as? String) ?? ""
                completion(summary)
            }
        )
    }
    
    /// Creates an empty action that just returns a default value
    private func createEmptyAction(completion: @escaping (Any) -> Void) -> Action {
        return AnyAction(
            systemPrompt: "",
            messages: [],
            message: Message(role: .user, content: ""),
            clearKVCache: false,
            modelType: .thinking,
            tokenFilter: nil,
            progressHandler: nil,
            prepare: { _ -> (Bool, Message?, String?) in return (true, nil, nil) },
            runCode: { _ in (false, "Error: Missing viewModel") },
            postAction: { _ in 
                completion("Error: Missing viewModel")
            }
        )
    }
}