/// Responsible for executing Actions in sequence against one or more LlamaModels.
actor ActionRunner {
    /// Shared singleton for running Actions.
    static let shared = ActionRunner()

    /// Execute an Action: clear KV cache if needed, stream generation,
    /// call runCode, then postAction with the correct result.
    func run(_ action: Action) async {
        // Model selection code remains the same
        let model: LlamaModel
        switch action.modelType {
        case .chat:
            model = await LlamaBridge.shared.getModel(id: "chat")
        case .thinking:
            model = await LlamaBridge.shared.getModel(id: "thinking")
        }
        
        if action.clearKVCache {
            model.clearContext()
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
            LoggerService.shared.debug("Starting stream processing for \(action.modelType)")
            let stream = await ResponseGenerator.shared.generate(
                llama: model,
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
                LoggerService.shared.debug("Stream completed successfully")
                isComplete = true
                timeoutTask.cancel()
                
                // Call postAction with the final response
                let (didRun, result) = action.runCode(on: accumulatedResponse)
                if didRun {
                    LoggerService.shared.debug("Calling postAction with processed result")
                    action.postAction(result)
                } else {
                    LoggerService.shared.debug("Calling postAction with raw response")
                    action.postAction(accumulatedResponse)
                }
            } catch {
                LoggerService.shared.error("Stream processing error: \(error.localizedDescription)")
                isComplete = true
                timeoutTask.cancel()
                
                // Still call postAction with whatever we have
                if !accumulatedResponse.isEmpty {
                    let (didRun, result) = action.runCode(on: accumulatedResponse)
                    if didRun {
                        action.postAction(result)
                    } else {
                        action.postAction(accumulatedResponse)
                    }
                }
            }
        } else {
            // Original fallback code for non-streaming case
            let response = await collectFullResponse(
                from: model,
                messages: action.messages,
                systemPrompt: action.systemPrompt,
                message: action.message
            )
            let (didRun, result) = action.runCode(on: response)
            if didRun {
                action.postAction(result)
            } else {
                action.postAction(response)
            }
        }
    }

    /// Execute multiple Actions in order.
    func runAll(_ actions: [Action]) async {
        for action in actions {
            await run(action)
        }
    }

    /// Helper to accumulate a streamed AsyncStream<String> into a single String.
    private func collectFullResponse(from model: LlamaModel, messages: [Message], systemPrompt: String,  message: Message) async -> String {
        var full = ""
        let stream = await ResponseGenerator.shared.generate(llama: model, history: messages, systemPrompt: systemPrompt, newUserMessage: message)
        for await token in stream {
            full += token
        }
        return full
    }
}

