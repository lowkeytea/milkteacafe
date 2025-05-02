import Foundation

/// A registry for managing available functions that can be called by the LLM
class FunctionRegistry {
    /// The shared singleton instance
    static let shared = FunctionRegistry()
    
    /// Default functions that are registered by default
    static let defaultFunctions: [FunctionProtocol.Type] = [
        SystemPromptFunction.self,
        NameFunction.self,
        VoiceFunction.self,
        NoOperationFunction.self
    ]
    
    /// Dictionary mapping function names to their handler implementations
    private var functions: [String: (([String: Any]) -> Any)] = [:]
    
    /// Private initializer for singleton
    private init() {}
    
    /// Register a new function with the registry
    /// - Parameters:
    ///   - name: The name of the function
    ///   - handler: The closure that implements the function's behavior
    func register(name: String, handler: @escaping ([String: Any]) -> Any) {
        functions[name] = handler
    }
    
    /// Register all default functions
    func registerDefaultFunctions() {
        for functionType in FunctionRegistry.defaultFunctions {
            let functionName = functionType.getDefinition().name
            register(name: functionName) { parameters in
                return functionType.execute(parameters: parameters) ?? false
            }
        }
    }
    
    /// Retrieve a function handler by name
    /// - Parameter name: The name of the function to retrieve
    /// - Returns: The function handler if found, nil otherwise
    func getFunction(name: String) -> (([String: Any]) -> Any)? {
        return functions[name]
    }
    
    /// Get a list of all registered function names
    /// - Returns: Array of function names
    func listFunctions() -> [String] {
        return Array(functions.keys)
    }
    
    /// Clear all registered functions
    func clear() {
        functions.removeAll()
    }
}
