import Foundation
import ObjectBox
import LowkeyTeaLLM

class ObjectBoxManager {
    static let shared = ObjectBoxManager()
    private(set) var chatBox: Box<Message>!
    private(set) var chatSegmentsBox: Box<MessageSegment>!
    var store: Store!
    
    private init() {
        setupStore()
    }
    
    private func setupStore() {
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask)[0]
            let storePath = documentsPath.appendingPathComponent("memory")
            
            store = try Store(directoryPath: storePath.path)
            chatBox = store.box(for: Message.self)
            chatSegmentsBox = store.box(for: MessageSegment.self)

        } catch {
            fatalError("Failed to setup ObjectBox store: \(error)")
        }
    }
}
