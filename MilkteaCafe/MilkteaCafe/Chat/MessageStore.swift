import Foundation
import ObjectBox

class MessageStore {
    static let shared = MessageStore()
    private let messages = ObjectBoxManager.shared.chatBox
    private let messageSegments = ObjectBoxManager.shared.chatSegmentsBox
    
    private init() {}
    
    /// Gets the total count of user messages in the chat history
    func getUserMessageCount() -> Int {
        guard let box = messages else {
            return 0
        }
        do {
            // Count messages where role is user and category is chat
            let count = try box.query {
                Message.role.isEqual(to: MessageRole.user.rawValue) &&
                Message.category.isEqual(to: MessageCategory.chat.rawValue)
            }
            .build()
            .count()
            
            return count
        } catch {
            print("Error counting user messages: \(error)")
            return 0
        }
    }
    
    func getRecentMessages(category: MessageCategory, limit: Int = 10) -> [Message] {
        guard let box = messages else {
            return []
        }
        do {
            let found = try box.query {
                Message.category.isEqual(to: category.rawValue)
            }
                .ordered(by: Message.timestamp, flags: [.descending])
                .build()
                .find(offset: 0, limit: limit)
            return found.reversed()
        } catch {
            return []
        }
    }
    
    func clearMessages() {
        guard let box = messages else {
            return
        }
        do {
            try box.removeAll()
        } catch {
            print("Error adding message: \(error)")
        }
    }
    
    func addMessage(_ message: Message) {
        guard let box = messages else {
            return
        }
        do {
            try box.put(message)
        } catch {
            print("Error adding message: \(error)")
        }
    }
}
