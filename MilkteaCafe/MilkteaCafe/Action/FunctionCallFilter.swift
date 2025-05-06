import Foundation
import LowkeyTeaLLM

/// Special token filter for function calling
/// Accumulates tokens until a complete JSON function call is detected
struct FunctionCallFilter: TokenFilter {
    private var buffer: String = ""
    
    mutating func process(token: String) -> [String] {
        buffer += token
        
        // Check if the buffer contains a complete JSON structure
        if isCompleteFunctionCall(buffer) {
            let complete = buffer
            buffer = ""
            return [complete]
        }
        
        return []
    }
    
    mutating func flush() -> [String] {
        if buffer.isEmpty {
            return []
        }
        
        let remaining = buffer
        buffer = ""
        return [remaining]
    }
    
    /// Helper to check if the buffer contains a valid function call JSON
    private func isCompleteFunctionCall(_ text: String) -> Bool {
        // Simple check for matching braces
        let openBraces = text.filter { $0 == "{" }.count
        let closeBraces = text.filter { $0 == "}" }.count
        
        // If we have matching braces and the outer structure seems complete
        if openBraces > 0 && openBraces == closeBraces {
            // Check if we can extract JSON that has name and arguments
            if let openBrace = text.firstIndex(of: "{"),
               let closeBrace = text.lastIndex(of: "}") {
                let jsonCandidate = String(text[openBrace...closeBrace])
                
                // Check if it has the required fields
                return jsonCandidate.contains("\"name\"") && jsonCandidate.contains("\"arguments\"")
            }
        }
        
        return false
    }
}
