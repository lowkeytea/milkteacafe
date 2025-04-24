import Foundation

struct Message: Identifiable, Equatable {
    let id: UUID
    let contentHash: Int
    let role: MessageRole
    var content: String
    let timestamp: Date
    
    init(role: MessageRole,
         content: String,
         timestamp: Date = Date(),
         isComplete: Bool = false,
         sequenceId: Int32? = nil,
         startPosition: Int32? = nil,
         endPosition: Int32? = nil,
         isProcessed: Bool = false,
         isProcessing: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.contentHash = content.hashValue
        self.timestamp = timestamp
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content &&
        lhs.contentHash == rhs.contentHash &&
        lhs.timestamp == rhs.timestamp
    }
}

enum MessageRole: String {
    case user = "user"
    case system = "system"
    case assistant = "assistant"
    case context = "context"
}

