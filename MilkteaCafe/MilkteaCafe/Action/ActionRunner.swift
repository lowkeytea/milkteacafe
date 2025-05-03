/// Responsible for executing Actions in sequence against one or more LlamaContexts.
actor ActionRunner {
    /// Shared singleton for running Actions.
    static let shared = ActionRunner()

    /**
     * Execute an Action with dynamic model loading for thinking operations
     *
     * This method handles:
     * 1. Dynamic loading of thinking model context when needed (chat model stays loaded)
     * 2. Proper cleanup of thinking model context when done to free memory
     * 3. Error handling to ensure thinking model is always released
     * 4. Streaming token generation and filtering
     *
     * The thinking model context is only loaded when needed and automatically unloaded
     * when all thinking operations complete, helping reduce memory usage.
     * Model weights are preserved for quick reuse.
     */
    func run(_ action: Action) async {
        // For thinking model, dynamically load/unload contexts
        if action.modelType == .thinking {
            // Acquire thinking model context before running
            let contextLoaded = await ModelManager.shared.acquireThinkingModel()
            guard contextLoaded else {
                LoggerService.shared.error("Failed to load thinking model context for action")
                return
            }
            
            do {
                // Execute action with context - using try to catch potential errors
                try await executeActionWithErrorHandling(action)
            } catch {
                LoggerService.shared.error("Error executing thinking action: \(error.localizedDescription)")
            }
            return
        }
        
        // For chat model, use standard execution
        await executeAction(action)
    }
    
    /// Execute an action with error handling
    private func executeActionWithErrorHandling(_ action: Action) async throws {
        // Create a task that can be cancelled
        let task = Task {
            await executeAction(action)
        }
        
        do {
            try await task.value
        } catch is CancellationError {
            LoggerService.shared.info("Action was cancelled")
            throw CancellationError()
        } catch {
            LoggerService.shared.error("Action execution failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Internal method to execute an action with the appropriate context
    private func executeAction(_ action: Action) async {
        await executeAction(action, continuation: nil)
    }
    
    /// Execute an action with a completion handler
    func executeAction(_ action: Action, continuation: ((Any) -> Void)?) async {
        // Context selection code
        let context: LlamaContext
        switch action.modelType {
        case .chat:
            context = await LlamaBridge.shared.getContext(id: "chat")
        case .thinking:
            context = await LlamaBridge.shared.getContext(id: "thinking")
        }
        
        if action.clearKVCache {
            await context.clearContext()
        }

        if let anyAction = action as? AnyAction, let filter = anyAction.tokenFilter {
            var accumulatedResponse = ""
            
            // Add timeout protection to prevent getting stuck
            var isComplete = false
            let timeoutTask = Task {
                do {
                    // Give it 30 seconds max to complete
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    if !isComplete {
                        LoggerService.shared.warning("Stream processing timed out, forcing completion")
                        isComplete = true
                    }
                } catch {
                    // Task was cancelled normally, ignore
                }
            }
            
            // Stream generated units through the filter
            #if DEBUG
            LoggerService.shared.debug("Starting stream processing for \(action.modelType) context")
            #endif
            let stream = await ResponseGenerator.shared.generate(
                llama: context,
                history: action.messages,
                systemPrompt: action.systemPrompt,
                newUserMessage: action.message,
                filter: filter
            )
            
            // Process each token/sentence
            do {
                for await unit in stream {
                    if Task.isCancelled { throw CancellationError() }
                    
                    accumulatedResponse += unit
                    anyAction.progressHandler?(unit)
                }
                
                // Stream completed normally
                #if DEBUG
                LoggerService.shared.debug("Stream completed successfully")
                #endif
                isComplete = true
                timeoutTask.cancel()
                
                // Call postAction with the final response
                let (didRun, result) = action.runCode(on: accumulatedResponse)
                let finalResult = didRun ? result : accumulatedResponse
                
                if didRun {
                    #if DEBUG
                    LoggerService.shared.debug("Calling postAction with processed result")
                    #endif
                    action.postAction(result)
                } else {
                    #if DEBUG
                    LoggerService.shared.debug("Calling postAction with raw response")
                    #endif
                    action.postAction(accumulatedResponse)
                }
                
                // Also call continuation if provided
                if let continuation = continuation {
                    continuation(finalResult)
                }
            } catch {
                LoggerService.shared.error("Stream processing error: \(error.localizedDescription)")
                isComplete = true
                timeoutTask.cancel()
                
                // Still call postAction with whatever we have
                if !accumulatedResponse.isEmpty {
                    let (didRun, result) = action.runCode(on: accumulatedResponse)
                    let finalResult = didRun ? result : accumulatedResponse
                    
                    if didRun {
                        action.postAction(result)
                    } else {
                        action.postAction(accumulatedResponse)
                    }
                    
                    // Also call continuation if provided, even in error case
                    if let continuation = continuation {
                        continuation(finalResult)
                    }
                } else if let continuation = continuation {
                    // Call continuation with error if no response
                    continuation(ActionError.executionFailed)
                }
            }
        } else {
            // Original fallback code for non-streaming case
            let response = await collectFullResponse(
                from: context,
                messages: action.messages,
                systemPrompt: action.systemPrompt,
                message: action.message
            )
            let (didRun, result) = action.runCode(on: response)
            let finalResult = didRun ? result : response
            
            if didRun {
                action.postAction(result)
            } else {
                action.postAction(response)
            }
            
            // Also call continuation if provided
            if let continuation = continuation {
                continuation(finalResult)
            }
        }
    }

    /**
     * Execute multiple Actions in order with optimized model loading
     *
     * This method is optimized to:
     * 1. Detect if all actions use the thinking model and handle them in a batch
     * 2. Load the thinking model context only once for all thinking actions
     * 3. Release the thinking model context only when all actions complete
     * 4. Handle mixed action types (thinking + chat) appropriately
     * 5. Ensure proper cleanup even when actions fail or are cancelled
     */
    func runAll(_ actions: [Action]) async {
        // Check if all actions are of the same type to optimize loading/unloading
        let allThinking = !actions.isEmpty && actions.allSatisfy { $0.modelType == .thinking }
        
        if allThinking {
            // Acquire thinking model context once for all actions
            let contextLoaded = await ModelManager.shared.acquireThinkingModel()
            guard contextLoaded else {
                LoggerService.shared.error("Failed to load thinking model context for batch actions")
                return
            }
            
            do {
                // Execute all actions with error handling
                for action in actions {
                    try? await executeActionWithErrorHandling(action)
                }
            } catch {
                LoggerService.shared.error("Error in batch thinking actions: \(error.localizedDescription)")
                // The deferred cleanup will still run after this catch block
            }
        } else {
            // Mixed action types - handle loading/unloading per action
            for action in actions {
                await run(action)
            }
        }
    }

    /// Helper to accumulate a streamed AsyncStream<String> into a single String.
    private func collectFullResponse(from context: LlamaContext, messages: [Message], systemPrompt: String, message: Message) async -> String {
        var full = ""
        let stream = await ResponseGenerator.shared.generate(
            llama: context,
            history: messages,
            systemPrompt: systemPrompt,
            newUserMessage: message
        )
        for await token in stream {
            full += token
        }
        return full
    }
}

