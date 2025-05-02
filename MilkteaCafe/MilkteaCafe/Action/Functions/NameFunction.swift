import Foundation

/// Class responsible for name-related function calls
class NameFunction: FunctionProtocol {
    /// Returns the function definition
    static func getDefinition() -> FunctionCall.FunctionDefinition {
        return FunctionCall.FunctionDefinition(
            name: "rememberName",
            description: "This function should be called when saving the name of the user or assistant.",
            parameters: [
                "name": FunctionCall.FunctionParameterDefinition(
                    type: "String",
                    description: "The name to save.",
                    required: true
                ),
                "user": FunctionCall.FunctionParameterDefinition(
                    type: "Boolean",
                    description: "true if saving the user's name; false if saving the assistant's name.",
                    required: true
                )
            ],
            returnType: "Boolean",
            returnDescription: "true if the name was successfully saved; otherwise false."
        )
    }
    
    /// Executes the function with the given parameters
    static func execute(parameters: [String: Any]) -> Any? {
        guard let name = parameters["name"] as? String,
              let isUser = parameters["user"] as? Bool else {
            return false
        }
        return NameAction.shared.rememberName(name: name, user: isUser)
    }
}
