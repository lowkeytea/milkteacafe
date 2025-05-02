import Foundation

/// Manager for handling system prompt operations
class SystemPromptManager {
    /// Shared singleton instance
    static let shared = SystemPromptManager()
    
    /// UserDefaults key for storing the system prompt
    private let systemPromptKey = "chatSystemPrompt"
    
    /// Default system prompt to use if none is saved
    private let defaultSystemPrompt = "You are a helpful, harmless, and honest AI assistant."
    
    /// Private initializer for singleton
    private init() {}
    
    /// Get the current system prompt from persistent storage
    func getSystemPrompt() -> String {
        return UserDefaults.standard.string(forKey: systemPromptKey) ?? defaultSystemPrompt
    }
    
    /// Update the system prompt and save to persistent storage
    /// - Parameter prompt: The new system prompt text
    /// - Returns: True if successfully updated, false otherwise
    @discardableResult
    func updateSystemPrompt(_ prompt: String) -> Bool {
        // Thread safety check - ensure we're on the main thread
        if !Thread.isMainThread {
            LoggerService.shared.warning("SystemPromptManager.updateSystemPrompt called from background thread")
            
            // Redirect to main thread
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            
            var result = false
            DispatchQueue.main.async {
                result = self.updateSystemPrompt(prompt)
                dispatchGroup.leave()
            }
            
            dispatchGroup.wait()
            return result
        }
        
        // Validate the prompt (optional - add validation logic if needed)
        guard !prompt.isEmpty else {
            LoggerService.shared.warning("Attempted to set empty system prompt")
            return false
        }
        
        // Update UserDefaults
        UserDefaults.standard.set(prompt, forKey: systemPromptKey)
        
        // Log success
        LoggerService.shared.info("System prompt updated successfully")
        
        // Post notification for other components to listen for
        NotificationCenter.default.post(
            name: .systemPromptDidChange,
            object: nil,
            userInfo: ["prompt": prompt]
        )
        
        return true
    }
}

// Define notification names as extension
extension Notification.Name {
    static let systemPromptDidChange = Notification.Name("systemPromptDidChange")
    static let voiceSupportSettingChanged = Notification.Name("voiceSupportSettingChanged")
}
