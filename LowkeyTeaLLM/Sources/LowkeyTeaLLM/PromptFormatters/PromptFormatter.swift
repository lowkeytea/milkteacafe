import Foundation

public protocol PromptFormatter {
    
    func format(messages: [LlamaMessage], systemPrompt: String?) -> String
    
    func checkStopSequence(_ text: String, tokenCount: Int, maxToken: Int) -> (String, String)?
    
    func estimateTokenCount(_ text: String) -> Int
    
    func clearStopBuffer()
    
    func formatForRole(message: LlamaMessage) -> String
    
    func roleToString(_ role: MessageRole) -> String
}
