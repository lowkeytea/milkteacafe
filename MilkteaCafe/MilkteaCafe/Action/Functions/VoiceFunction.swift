import Foundation

/// Class responsible for voice-related function calls
class VoiceFunction: FunctionProtocol {
    /// Returns the function definition
    static func getDefinition() -> FunctionCall.FunctionDefinition {
        return FunctionCall.FunctionDefinition(
            name: "enableVoiceSupport",
            description: "This function should be called to enable or disable text-to-speech voice support.",
            parameters: [
                "enabled": FunctionCall.FunctionParameterDefinition(
                    type: "Boolean",
                    description: "true to enable voice support; false to disable it.",
                    required: true
                )
            ],
            returnType: "Boolean",
            returnDescription: "true if the voice support setting was successfully changed; otherwise false."
        )
    }
    
    /// Executes the function with the given parameters
    static func execute(parameters: [String: Any]) -> Any? {
        guard let enabled = parameters["enabled"] as? Bool else {
            return false
        }
        return VoiceAction.shared.enableVoiceSupport(enabled: enabled)
    }
}
