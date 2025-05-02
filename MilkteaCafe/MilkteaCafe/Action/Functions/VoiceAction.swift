import Foundation

/// Class responsible for voice-related function calls
class VoiceAction {
    /// Singleton instance
    static let shared = VoiceAction()
    
    /// UserDefaults key
    private let ttsEnabledKey = "ttsEnabled"
    
    /// Private initializer for singleton
    private init() {}
    
    /// Enable or disable voice support
    func enableVoiceSupport(enabled: Bool) -> Bool {
        // Log the operation
        LoggerService.shared.info("Setting voice support to: \(enabled)")
        
        // Thread safety check - ensure we're on the main thread
        if !Thread.isMainThread {
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            
            var result = false
            DispatchQueue.main.async {
                result = self.enableVoiceSupport(enabled: enabled)
                dispatchGroup.leave()
            }
            
            dispatchGroup.wait()
            return result
        }
        
        // Store the setting in UserDefaults
        UserDefaults.standard.set(enabled, forKey: ttsEnabledKey)
        
        // Notify any listeners
        NotificationCenter.default.post(
            name: .voiceSupportSettingChanged,
            object: nil,
            userInfo: ["enabled": enabled]
        )
        
        return true
    }
    
    /// Get the current voice support setting
    func isVoiceSupportEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: ttsEnabledKey)
    }
}
