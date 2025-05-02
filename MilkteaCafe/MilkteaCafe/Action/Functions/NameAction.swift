import Foundation

/// Class responsible for name-related function calls
class NameAction {
    /// Singleton instance
    static let shared = NameAction()
    
    /// UserDefaults keys
    private let userNameKey = "userName"
    private let assistantNameKey = "assistantName"
    
    /// Private initializer for singleton
    private init() {}
    
    /// Remember a name for either the user or assistant
    func rememberName(name: String, user: Bool) -> Bool {
        // Log the operation
        let target = user ? "user" : "assistant"
        LoggerService.shared.info("Remembering \(target) name: \(name)")
        
        // Thread safety check - ensure we're on the main thread
        if !Thread.isMainThread {
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            
            var result = false
            DispatchQueue.main.async {
                result = self.rememberName(name: name, user: user)
                dispatchGroup.leave()
            }
            
            dispatchGroup.wait()
            return result
        }
        
        // Store the name in UserDefaults
        let key = user ? userNameKey : assistantNameKey
        UserDefaults.standard.set(name, forKey: key)
        
        // Notify any listeners
        NotificationCenter.default.post(
            name: .nameDidChange,
            object: nil,
            userInfo: [
                "name": name,
                "isUser": user
            ]
        )
        
        return true
    }
    
    /// Get the user's name if available
    func getUserName() -> String? {
        return UserDefaults.standard.string(forKey: userNameKey)
    }
    
    /// Get the assistant's name if available
    func getAssistantName() -> String? {
        return UserDefaults.standard.string(forKey: assistantNameKey)
    }
}

// Define notification name
extension Notification.Name {
    static let nameDidChange = Notification.Name("nameDidChange")
}
