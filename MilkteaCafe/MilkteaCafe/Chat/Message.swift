import Foundation
import LowkeyTeaLLM
import ObjectBox

// objectbox: entity
class Message: Identifiable, Equatable {
    var id: Id = 0
    // objectbox: transient
    let equatableId: UUID
    // objectbox: convert = { "default": ".user" }
    var role: MessageRole
    // objectbox: convert = { "default": ".chat" }
    var category: MessageCategory
    var content: String
    var timestamp: Date
    // objectbox: backlink = "parentMessage"
    var segments: ToMany<MessageSegment> = nil
    
    init() {
        self.role = .user
        self.equatableId = UUID()
        self.category = .chat
        self.content = ""
        self.timestamp = Date()
    }
    
    init(llamaMessage: LlamaMessage) {
        self.role = llamaMessage.role
        self.content = llamaMessage.content
        self.category = llamaMessage.category
        self.equatableId = llamaMessage.equatableId
        self.timestamp = llamaMessage.timestamp
    }
    
    init(role: MessageRole, category: MessageCategory = .chat, content: String, date: Date = Date()) {
        self.role = role
        self.equatableId = UUID()
        self.category = category
        self.content = content
        self.timestamp = date
    }
    
    
    func toLlamaMessage() -> LlamaMessage {
        return LlamaMessage(role: self.role, category: self.category, content: self.content, date: self.timestamp)
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.category == rhs.category &&
        lhs.content == rhs.content &&
        lhs.timestamp == rhs.timestamp &&
        lhs.equatableId == rhs.equatableId
    }
}
