import ObjectBox
import Foundation
import LowkeyTeaLLM

// MessageSegment represents a single segment of a message with its own embedding
// objectbox: entity
class MessageSegment {
    var id: Id = 0
    
    // objectbox: backlink = "memories"
    var parentMessage: ToOne<Message> = nil

    // objectbox: convert = { "default": ".chat" }
    var category: MessageCategory
    // Content and position info
    var content: String
    var position: Int  // Position in the original message
    var createdAt: Date
    
    // objectbox:hnswIndex: dimensions=100, neighborsPerNode=64, indexingSearchCount=400, distanceType="cosine"
    var embedding: [Float]
    
    init() {
        self.content = ""
        self.category = .chat
        self.position = 0
        self.createdAt = Date()
        self.embedding = Array(repeating: 0.0, count: 100)
    }
    
    init(content: String, category: MessageCategory, position: Int, embedding: [Float], createdAt: Date = Date()) {
        self.content = content
        self.category = category
        self.position = position
        self.embedding = embedding
        self.createdAt = createdAt
    }
}
