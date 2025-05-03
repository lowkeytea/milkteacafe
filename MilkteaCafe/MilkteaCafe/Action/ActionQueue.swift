import Foundation

/**
 * Represents an action node in the dependency graph.
 * Each node contains an action and its dependencies on other actions.
 */
struct ActionNode {
    /// Unique identifier for this action node
    let id: String
    
    /// The action to execute
    let action: Action
    
    /// IDs of actions this one depends on
    let dependencies: [String]
    
    /// Type of model this action requires
    var modelType: ModelType {
        return action.modelType
    }
    
    /// Result storage
    var result: Any?
    
    /// Completion handler
    var completion: ((Any) -> Void)?
    
    /// Creates a new action node
    init(id: String, action: Action, dependencies: [String] = [], completion: ((Any) -> Void)? = nil) {
        self.id = id
        self.action = action
        self.dependencies = dependencies
        self.completion = completion
    }
}

/**
 * Manages a queue of actions with dependencies.
 * Ensures actions are executed in the correct order based on their dependencies.
 * Handles parallel execution of independent actions.
 */
actor ActionQueue {
    /// Actions waiting to be processed
    private var pendingNodes: [ActionNode] = []
    
    /// Currently running action tasks, keyed by node ID
    private var runningTasks: [String: Task<Any, Error>] = [:]
    
    /// Completed action IDs and their results
    private var completedResults: [String: Any] = [:]
    
    /// Queue processing task
    private var processingTask: Task<Void, Never>?
    
    /// Whether the queue is currently processing
    private var isProcessing = false
    
    /// Enqueues an action node with its dependencies
    func enqueue(_ node: ActionNode) {
        pendingNodes.append(node)
        
        // Start queue processing if not already running
        if !isProcessing {
            startProcessing()
        }
    }
    
    /// Enqueues multiple action nodes at once
    func enqueueAll(_ nodes: [ActionNode]) async {
        pendingNodes.append(contentsOf: nodes)
        
        // Start queue processing if not already running
        if !isProcessing {
            startProcessing()
        }
    }
    
    /// Starts the queue processing loop
    private func startProcessing() {
        guard !isProcessing else { return }
        
        isProcessing = true
        processingTask = Task {
            await processQueue()
        }
    }
    
    /// Gets the result of a completed action
    func getResult(for nodeId: String) -> Any? {
        let result = completedResults[nodeId]
        if result == nil {
            LoggerService.shared.warning("ActionQueue: getResult for node \(nodeId) returned nil - result not found")
        } else {
            #if DEBUG
            LoggerService.shared.debug("ActionQueue: getResult for node \(nodeId) returned result type: \(type(of: result!))")
            #endif
        }
        return result
    }
    
    /// Checks if all nodes have been processed
    func allNodesComplete() -> Bool {
        return pendingNodes.isEmpty && runningTasks.isEmpty
    }
    
    /// The main queue processing loop
    private func processQueue() async {
        while !pendingNodes.isEmpty || !runningTasks.isEmpty {
            // Find nodes whose dependencies are satisfied
            let readyNodes = findReadyNodes()
            
            // Start tasks for ready nodes
            for node in readyNodes {
                // Remove from pending
                pendingNodes.removeAll { $0.id == node.id }
                
                // Create a task for this node
                let task = Task<Any, Error> {
                    // Wait for thinking model if needed
                    if node.modelType == .thinking {
                        let acquired = await ModelManager.shared.acquireThinkingModel()
                        guard acquired else {
                            throw ActionError.modelLoadFailure
                        }
                    }
                    
                    // Gather dependencies for this node right before execution
                    var dependencies: [String: Any] = [:]
                    for depId in node.dependencies {
                        if let depResult = completedResults[depId] {
                            dependencies[depId] = depResult
                            #if DEBUG
                            LoggerService.shared.debug("ActionQueue: Providing dependency \(depId) to node \(node.id) with result type: \(type(of: depResult))")
                            #endif
                        } else {
                            LoggerService.shared.warning("ActionQueue: Missing dependency \(depId) for node \(node.id)")
                        }
                    }
                    
                    // Create a mutable copy of the action to prepare
                    var preparedAction = node.action
                    
                    // Prepare the action with its dependencies
                    let prepSuccess = await preparedAction.prepareForExecution(with: dependencies)
                    if !prepSuccess {
                        LoggerService.shared.warning("ActionQueue: Failed to prepare action for node \(node.id)")
                    }
                    
                    // Execute the prepared action
                    return await executeAction(preparedAction)
                }
                
                // Store the running task
                runningTasks[node.id] = task
            }
            
            // Check for completed tasks - make a copy to avoid mutation during iteration
            let tasksCopy = runningTasks
            for (nodeId, task) in tasksCopy {
                if task.isCancelled {
                    // Task was cancelled, handle it
                    completedResults[nodeId] = ActionError.cancelled
                    runningTasks.removeValue(forKey: nodeId)
                    continue
                }
                
                // Create a non-blocking check for completion
                let checkTask = Task {
                    do {
                        let result = try await task.value
                        completedResults[nodeId] = result
                        runningTasks.removeValue(forKey: nodeId)
                        
                        #if DEBUG
                        LoggerService.shared.debug("ActionQueue: Successfully completed task for node \(nodeId) with result type: \(type(of: result))")
                        #endif
                        // Explicitly check which pending nodes this completion might unblock
                        let unblocked = pendingNodes.filter { node in
                            node.dependencies.contains(nodeId) 
                        }
                        if !unblocked.isEmpty {
                            #if DEBUG
                            LoggerService.shared.debug("ActionQueue: Completion of \(nodeId) may unblock nodes: \(unblocked.map { $0.id }.joined(separator: ", "))")
                            #endif
                            for unblockedNode in unblocked {
                                let stillBlocked = unblockedNode.dependencies.filter { depId in
                                    !completedResults.keys.contains(depId)
                                }
                                if !stillBlocked.isEmpty {
                                    #if DEBUG
                                    LoggerService.shared.debug("ActionQueue: Node \(unblockedNode.id) still waiting for: \(stillBlocked.joined(separator: ", "))")
                                    #endif
                                }
                            }
                        }
                        
                        // Call completion handler if present
                        if let node = readyNodes.first(where: { $0.id == nodeId }),
                           let completion = node.completion {
                            #if DEBUG
                            LoggerService.shared.debug("ActionQueue: Calling completion handler for node \(nodeId)")
                            #endif
                            completion(result)
                        }
                    } catch {
                        LoggerService.shared.error("Action node \(nodeId) failed: \(error.localizedDescription)")
                        // Still mark as completed to unblock dependencies
                        completedResults[nodeId] = ActionError.executionFailed
                        runningTasks.removeValue(forKey: nodeId)
                    }
                }
            }
            
            // Throttle loop to prevent CPU spinning
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Check if we should continue
            try? Task.checkCancellation()
        }
        
        // Queue is empty and no tasks are running
        isProcessing = false
    }
    
    /// Finds nodes whose dependencies are all completed
    private func findReadyNodes() -> [ActionNode] {
        let readyNodes = pendingNodes.filter { node in
            // A node is ready if all its dependencies are completed
            let allDependenciesSatisfied = node.dependencies.allSatisfy { depId in
                let isSatisfied = completedResults.keys.contains(depId)
                if !isSatisfied {
                    #if DEBUG
                    LoggerService.shared.debug("ActionQueue: Node \(node.id) is waiting for dependency \(depId)")
                    #endif
                }
                return isSatisfied
            }
            
            if allDependenciesSatisfied && !node.dependencies.isEmpty {
                #if DEBUG
                LoggerService.shared.debug("ActionQueue: Node \(node.id) has all dependencies satisfied: \(node.dependencies.joined(separator: ", "))")
                #endif
            }
            
            return allDependenciesSatisfied
        }
        
        if !readyNodes.isEmpty {
            #if DEBUG
            LoggerService.shared.debug("ActionQueue: Found \(readyNodes.count) ready nodes: \(readyNodes.map { $0.id }.joined(separator: ", "))")
            #endif
        }
        
        return readyNodes
    }
    
    /// Executes a single action and returns its result
    private func executeAction(_ action: Action) async -> Any {
        return await withCheckedContinuation { continuation in
            Task {
                // Call the original ActionRunner to execute this action
                await ActionRunner.shared.executeAction(action, continuation: { result in
                    continuation.resume(returning: result)
                })
            }
        }
    }
    
    /// Cancels all pending and running actions
    func cancelAll() {
        for (_, task) in runningTasks {
            task.cancel()
        }
        
        pendingNodes.removeAll()
        processingTask?.cancel()
        isProcessing = false
    }
    
    /// Ensures proper cleanup when the queue is no longer needed
    func cleanup() async {
        // Cancel all tasks
        cancelAll()
    }
    
    deinit {
        // We can't use async in deinit, so log a warning and use a static method
        // Cancel active tasks
        for (_, task) in runningTasks {
            task.cancel()
        }
    }
}

/// Errors that can occur during action processing
enum ActionError: Error {
    case modelLoadFailure
    case executionFailed
    case dependencyFailed
    case cancelled
}
