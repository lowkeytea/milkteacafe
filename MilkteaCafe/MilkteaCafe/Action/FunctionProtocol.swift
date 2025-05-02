import Foundation

/// Protocol that all function classes must implement
protocol FunctionProtocol {
    /// Returns the function definition
    static func getDefinition() -> FunctionCall.FunctionDefinition
    
    /// Executes the function with the given parameters
    static func execute(parameters: [String: Any]) -> Any?
}
