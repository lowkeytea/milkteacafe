import Foundation

/// Represents a chat message in the conversation
struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }
    
    let id = UUID()
    let role: Role
    var content: String
} 