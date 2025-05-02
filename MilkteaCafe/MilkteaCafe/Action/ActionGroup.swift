protocol ActionGroup {
    /// Execute the full sequence of actions
    func execute(with initialMessage: Message) async
    
    /// Access final results from all actions
    var results: [String: Any] { get }
    
    /// Subscribe to receive tokens from specific action types
    func subscribeToProgress(for actionId: String, handler: @escaping (String) -> Void)
}
