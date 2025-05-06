import Foundation
import LowkeyTeaLLM

/// A lightweight, view-friendly representation of a chat message or summary
struct ViewableMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    /// Initialize from a persistent Message object
    init(from message: Message) {
        self.id = message.equatableId
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
    }
    
    init(from message: LlamaMessage) {
        self.id = message.equatableId
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
    }

    /// Initialize for a temporary or placeholder message
    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
} 
