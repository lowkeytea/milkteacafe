import Foundation

/// Class responsible for system prompt function calls
class SystemPromptFunction: FunctionProtocol {
    /// Returns the function definition
    static func getDefinition() -> FunctionCall.FunctionDefinition {
        let systemPrompt = SystemPromptManager.shared.getSystemPrompt()
        return FunctionCall.FunctionDefinition(
            name: "changeSystemPrompt",
            description: "Change the system prompt text.  Be mindful if the user is asking to update some of the text or change it completely. The original system prompt is: **\(systemPrompt)**. Only change it if the user explicitly mentions system prompt in their request.",
            parameters: [
                "prompt": FunctionCall.FunctionParameterDefinition(
                    type: "String",
                    description: "The new system prompt text.",
                    required: true
                )
            ],
            returnType: "Boolean",
            returnDescription: "true if the prompt was successfully changed; otherwise false."
        )
    }
    
    /// Executes the function with the given parameters
    static func execute(parameters: [String: Any]) -> Any? {
        guard let prompt = parameters["prompt"] as? String else {
            return false
        }
        return SystemPromptManager.shared.updateSystemPrompt(prompt)
    }
}
