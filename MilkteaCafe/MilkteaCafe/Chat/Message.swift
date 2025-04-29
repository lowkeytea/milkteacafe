import Foundation
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
    
    init(role: MessageRole, category: MessageCategory = .chat, content: String, date: Date = Date()) {
        self.role = role
        self.equatableId = UUID()
        self.category = category
        self.content = content
        self.timestamp = date
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

enum MessageRole: String {
    case user = "user"
    case system = "system"
    case assistant = "assistant"
}

enum MessageCategory: String {
    case chat = "chat"
    case userInfo = "userInfo"
    case assistantInfo = "assistantInfo"
    case summary = "summary"
}

