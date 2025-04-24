import Foundation

protocol PromptFormatter {
    
    func format(messages: [Message], systemPrompt: String?) -> String
    
    func checkStopSequence(_ text: String, tokenCount: Int, maxToken: Int) -> (String, String)?
    
    func estimateTokenCount(_ text: String) -> Int
    
    func clearStopBuffer()
    
    func formatForRole(message: Message) -> String
    
    func getGrammarDefinition() -> String
    
    func roleToString(_ role: MessageRole) -> String
}
