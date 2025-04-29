import Foundation
class GemmaPromptFormatter: PromptFormatter {
    func formatForRole(message: Message) -> String {
        formatForRole(message: message, addSystem: "")
    }
    
    private static let TOKEN_COMPONENTS = [
        "begin_of_text", "start_header_id", "end_header_id",
        "eot_id", "begin", "end"
    ]
    
    private static let ROLE_SEQUENCES = [
        "user:", "assistant:", "system:",
        "\nuser", "\nassistant", "\nsystem"
    ]
    
    private static let TOKEN_PATTERN = #"<\\s*[^>]+\\s*>\\s*$"#
    
    private static let BEGIN_OF_HEADER = "<start_of_turn>"
    private static let END_OF_HEADER = "<end_of_turn>"
    private static let USER = "user"
    private static let ASSISTANT = "model"
    private static let BOS = "<bos>"
    
    private var stopBuffer: String = ""
    
    func format(messages: [Message], systemPrompt: String?) -> String {
        var prompt = ""
        var systemContent = ""
        let allowedPromptTokens = LlamaConfig.shared.contextSize - LlamaConfig.shared.maxTokens
        
        // Extract system message if present
        var messagesToProcess = messages
        if let systemIndex = messages.firstIndex(where: { $0.role == .system }) {
            systemContent = messages[systemIndex].content
            messagesToProcess.remove(at: systemIndex)
            // Add BOS token only at the start
            prompt += GemmaPromptFormatter.BOS
        }
        
        // We'll collect messages along with their token counts.
        var selectedMessages: [(formatted: String, tokenCount: Int)] = []
        
        // If first message is user message, combine with system prompt
        if let firstMessage = messagesToProcess.first, firstMessage.role == .user {
            prompt += formatForRole(message: firstMessage, addSystem: systemContent)
            messagesToProcess.removeFirst()
        } else if let firstMessage = messagesToProcess.first, firstMessage.role == .assistant {
            prompt += formatForRole(message: Message(role: .user, content: systemContent), addSystem: "")
        }
        
        guard let latestMessage = messagesToProcess.last else {
            prompt += "\(GemmaPromptFormatter.BEGIN_OF_HEADER)\(GemmaPromptFormatter.ASSISTANT)\n"
            return prompt
        }
        
        let latestFormatted = formatForRole(message: latestMessage)
        let latestTokenCount = estimateTokenCount(latestFormatted)
        selectedMessages.append((latestFormatted, latestTokenCount))
        var totalTokens = latestTokenCount
        
        for message in messagesToProcess.dropLast().reversed() {
            let formatted = formatForRole(message: message)
            let tokenCount = estimateTokenCount(formatted)
            
            if totalTokens + tokenCount <= allowedPromptTokens {
                selectedMessages.append((formatted, tokenCount))
                totalTokens += tokenCount
            } else {
                // Skip messages that would exceed our limit.
                continue
            }
        }
        
        selectedMessages.reverse()
        
        // Process remaining messages normally
        for comp in selectedMessages {
            prompt += comp.formatted
        }
        
        // Add final assistant header
        prompt += "\(GemmaPromptFormatter.BEGIN_OF_HEADER)\(GemmaPromptFormatter.ASSISTANT)\n"
        return prompt
    }
    
    func formatForRole(message: Message, addSystem: String = "") -> String {
        switch message.role {
        case .user:
            var content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !addSystem.isEmpty {
                content = "\(addSystem)\n\(content)"
            }
            return "\(GemmaPromptFormatter.BEGIN_OF_HEADER)\(GemmaPromptFormatter.USER)\n\(content)\n\(GemmaPromptFormatter.END_OF_HEADER)\n"
            
        case .assistant:
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(GemmaPromptFormatter.BEGIN_OF_HEADER)\(GemmaPromptFormatter.ASSISTANT)\n\(content)\n\(GemmaPromptFormatter.END_OF_HEADER)\n"
            
        default:
            return ""
        }
    }
    
    func roleToString(_ role: MessageRole) -> String {
        switch role {
        case .user:
            return GemmaPromptFormatter.USER
        case .assistant:
            return GemmaPromptFormatter.ASSISTANT
        case .system:
            return GemmaPromptFormatter.USER
        }
    }
    
    func checkStopSequence(_ text: String, tokenCount: Int, maxToken: Int) -> (String, String)? {
        // Check for END_OF_HEADER first
        if text.hasSuffix(GemmaPromptFormatter.END_OF_HEADER) {
            return (String(text.dropLast(GemmaPromptFormatter.END_OF_HEADER.count)), GemmaPromptFormatter.END_OF_HEADER)
        }
        
        // Check role-based sequences
        for sequence in Self.ROLE_SEQUENCES {
            if let range = text.range(of: sequence, options: .caseInsensitive) {
                return (String(text[..<range.lowerBound]), sequence)
            }
        }
        
        // Check for formatted tokens
        if let regex = try? Regex(Self.TOKEN_PATTERN),
           let match = text.firstMatch(of: regex) {
            let token = text[match.range]
            return (String(text[..<match.range.lowerBound]), String(token))
        }
        
        return nil
    }
    
    func estimateTokenCount(_ text: String) -> Int {
        return Int(ceil(Double(text.count) / 4.0))
    }
    
    func clearStopBuffer() {
        stopBuffer = ""
    }
    
    func getGrammarDefinition() -> String {
        return #"""
        root   ::= object
        value  ::= object | array | string | number | ("true" | "false" | "null") ws

        object ::=
          "{" ws (
                    string ":" ws value
            ("," ws string ":" ws value)*
          )? "}" ws

        array  ::=
          "[" ws (
                    value
            ("," ws value)*
          )? "]" ws

        string ::=
          "\"" (
            [^"\\\x7F\x00-\x1F] |
            "\\" (["\\bfnrt] | "u" [0-9a-fA-F]{4}) # escapes
          )* "\"" ws

        number ::= ("-"? ([0-9] | [1-9] [0-9]{0,15})) ("." [0-9]+)? ([eE] [-+]? [0-9] [1-9]{0,15})? ws

        # Optional space: by convention, applied in this grammar after literal chars when allowed
        ws ::= | " " | "\n" [ \t]{0,20}
        """#
    }
}
