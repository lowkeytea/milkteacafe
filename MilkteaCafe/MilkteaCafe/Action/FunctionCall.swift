import Foundation
import LowkeyTeaLLM

/// A class for handling function calling functionality with LLMs
class FunctionCall {
    // Available functions and their definitions
    private var availableFunctions: [FunctionDefinition] = []
    private var systemPrompt: String = ""
    private var isBuilt: Bool = false
    
    // Store the initial message for potential function chaining
    private var initialMessage: LlamaMessage? = nil
    
    /// Definition for a callable function
    struct FunctionDefinition {
        let name: String
        let description: String
        let parameters: [String: FunctionParameterDefinition]
        let returnType: String
        let returnDescription: String
    }
    
    /// Definition for a function parameter
    struct FunctionParameterDefinition {
        let type: String
        let description: String
        let required: Bool
    }
    
    /// Initialize with an empty set of functions
    init() {}
    
    /// Add a single function definition
    @discardableResult
    func addFunction(
        name: String,
        description: String,
        parameters: [String: FunctionParameterDefinition],
        returnType: String,
        returnDescription: String
    ) -> FunctionCall {
        availableFunctions.append(
            FunctionDefinition(
                name: name,
                description: description,
                parameters: parameters,
                returnType: returnType,
                returnDescription: returnDescription
            )
        )
        return self
    }
    
    /// Add a predefined function definition
    @discardableResult
    func addFunction(_ function: FunctionDefinition) -> FunctionCall {
        availableFunctions.append(function)
        return self
    }
    
    /// Build the function call system with the added functions
    @discardableResult
    func build() -> FunctionCall {
        systemPrompt = buildSystemPrompt()
        isBuilt = true
        return self
    }
    
    /// Convenience method to add standard functions and build
    @discardableResult
    func addStandardFunctions() -> FunctionCall {
        // Add function definitions from all default functions
        for functionType in FunctionRegistry.defaultFunctions {
            addFunction(functionType.getDefinition())
        }
        
        return self
    }
    
    /// Build the system prompt dynamically from the function definitions
    private func buildSystemPrompt() -> String {
        var prompt = """
        You are a function-calling AI. You have exactly \(availableFunctions.count) functions available. For any single user request, choose **one** function to invoke. When you call a function, respond **only** with a JSON object containing the "name" of the function and an "arguments" map. Do **not** include any extra text.

        **Available Functions**

        """
        
        // Add each function's definition to the prompt
        for function in availableFunctions {
            prompt += "\n\n**\(function.name)(\(formatParameters(function.parameters))) → \(function.returnType)**\n\n"
            prompt += "**Description**\n\(function.description)\n\n"
            
            if !function.parameters.isEmpty {
                prompt += "**Parameters**\n\n"
                
                for (paramName, paramDef) in function.parameters {
                    let requiredText = paramDef.required ? "required" : "optional"
                    prompt += "* \(paramName) (*\(paramDef.type)*, \(requiredText)) – \(paramDef.description)\n"
                }
                prompt += "\n"
            }
            
            prompt += "**Returns**\n\n"
            prompt += "* *\(function.returnType)* – \(function.returnDescription)\n"
        }
        
        // Add the output format instructions
        prompt += """
        
        **Function-Call Output Format**
        When invoking a function, output exactly:

        {
          "name": "<functionName>",
          "arguments": {
            /* key/value pairs matching the parameter list */
          }
        }
        """
        
        return prompt
    }
    
    /// Helper to format the parameters for display in the prompt
    private func formatParameters(_ parameters: [String: FunctionParameterDefinition]) -> String {
        if parameters.isEmpty {
            return ""
        }
        
        return parameters.map { paramName, paramDef in 
            "\(paramName): \(paramDef.type)" 
        }.joined(separator: ", ")
    }
    
    /// Get the system prompt for use in an Action
    func getSystemPrompt() -> String {
        if !isBuilt {
            LoggerService.shared.warning("FunctionCall.getSystemPrompt called before build() - building now")
            build()
        }
        return systemPrompt
    }
    
    /// Process the LLM's JSON response to extract and execute the function call
    func processResponse(_ response: String, initialMessage: LlamaMessage? = nil) -> (didRun: Bool, result: Any) {
        // Store the initial message for potential use in function implementations
        if let initialMessage = initialMessage {
            self.initialMessage = initialMessage
        }
        
        // Clean up the response to handle potential extra text
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to extract just the JSON part if there's any wrapper text
        let jsonString: String
        if let openBrace = trimmedResponse.firstIndex(of: "{"),
           let closeBrace = trimmedResponse.lastIndex(of: "}") {
            jsonString = String(trimmedResponse[openBrace...closeBrace])
        } else {
            jsonString = trimmedResponse
        }
        
        // Try to decode the JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            LoggerService.shared.error("Failed to convert response to data: \(jsonString)")
            return (false, "Invalid JSON response")
        }
        
        do {
            LoggerService.shared.debug("Data for function call: \(jsonString)")
            let decoder = JSONDecoder()
            let functionCall = try decoder.decode(FunctionCallResponse.self, from: jsonData)
            
            // Execute the appropriate function using the registry
            if let handler = FunctionRegistry.shared.getFunction(name: functionCall.name) {
                let result = handler(functionCall.arguments)
                
                // Return success with the function result
                return (true, [
                    "functionCalled": functionCall.name,
                    "result": result
                ])
            } else {
                LoggerService.shared.warning("Function not found in registry: \(functionCall.name)")
                return (false, "Function not found: \(functionCall.name)")
            }
            
        } catch {
            LoggerService.shared.error("Failed to decode function call: \(error.localizedDescription)")
            return (false, "Invalid function call format: \(error.localizedDescription)")
        }
    }
    
    /// Register the standard functions with the FunctionRegistry
    func registerStandardFunctions() {
        FunctionRegistry.shared.registerDefaultFunctions()
    }
}
