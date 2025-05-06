import Foundation

public class LlamaMessage: Identifiable, Equatable {
    public let equatableId: UUID
    public let role: MessageRole
    public let category: MessageCategory
    public let content: String
    public let timestamp: Date

    public init() {
        self.role = .user
        self.equatableId = UUID()
        self.category = .chat
        self.content = ""
        self.timestamp = Date()
    }
    
    public init(role: MessageRole, category: MessageCategory = .chat, content: String, date: Date = Date()) {
        self.role = role
        self.equatableId = UUID()
        self.category = category
        self.content = content
        self.timestamp = date
    }
    
    public static func == (lhs: LlamaMessage, rhs: LlamaMessage) -> Bool {
        return lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.category == rhs.category &&
        lhs.content == rhs.content &&
        lhs.timestamp == rhs.timestamp &&
        lhs.equatableId == rhs.equatableId
    }
}

public enum MessageRole: String {
    case user = "user"
    case system = "system"
    case assistant = "assistant"
}

public enum MessageCategory: String {
    case chat = "chat"
    case userInfo = "userInfo"
    case assistantInfo = "assistantInfo"
    case summary = "summary"
}

