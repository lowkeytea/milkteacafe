import Foundation

/// Class responsible for no-operation function calls
class NoOperationFunction: FunctionProtocol {
    /// Returns the function definition
    static func getDefinition() -> FunctionCall.FunctionDefinition {
        return FunctionCall.FunctionDefinition(
            name: "noOperation",
            description: "This function should be called when no specific action is needed. It's a no-operation function.",
            parameters: [:],
            returnType: "Boolean",
            returnDescription: "Always returns true."
        )
    }
    
    /// Executes the function with the given parameters
    static func execute(parameters: [String: Any]) -> Any? {
        LoggerService.shared.info("No-operation function called")
        return true
    }
}
