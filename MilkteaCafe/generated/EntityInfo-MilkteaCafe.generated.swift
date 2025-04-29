// Generated using the ObjectBox Swift Generator — https://objectbox.io
// DO NOT EDIT

// swiftlint:disable all
import ObjectBox
import Foundation

// MARK: - Entity metadata

extension Message: ObjectBox.Entity {}
extension MessageSegment: ObjectBox.Entity {}

extension Message: ObjectBox.__EntityRelatable {
    internal typealias EntityType = Message

    internal var _id: EntityId<Message> {
        return EntityId<Message>(self.id.value)
    }
}

extension Message: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = MessageBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static var entityInfo = ObjectBox.EntityInfo(name: "Message", id: 1)

    internal static var entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: Message.self, id: 1, uid: 7304039349432266496)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 5503711839563083776)
        try entityBuilder.addProperty(name: "role", type: PropertyType.string, id: 2, uid: 647092059768449024)
        try entityBuilder.addProperty(name: "category", type: PropertyType.string, id: 3, uid: 4475357643649253120)
        try entityBuilder.addProperty(name: "content", type: PropertyType.string, id: 4, uid: 6214067988967140352)
        try entityBuilder.addProperty(name: "timestamp", type: PropertyType.date, id: 5, uid: 2934593687437153792)

        try entityBuilder.lastProperty(id: 5, uid: 2934593687437153792)
    }
}

extension Message {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { Message.id == myId }
    internal static var id: Property<Message, Id, Id> { return Property<Message, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { Message.role.startsWith("X") }
    internal static var role: Property<Message, String, Void> { return Property<Message, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { Message.category.startsWith("X") }
    internal static var category: Property<Message, String, Void> { return Property<Message, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { Message.content.startsWith("X") }
    internal static var content: Property<Message, String, Void> { return Property<Message, String, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { Message.timestamp > 1234 }
    internal static var timestamp: Property<Message, Date, Void> { return Property<Message, Date, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Use `Message.segments` to refer to this ToMany relation property in queries,
    /// like when using `QueryBuilder.and(property:, conditions:)`.

    internal static var segments: ToManyProperty<MessageSegment> { return ToManyProperty(.valuePropertyId(7)) }


    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == Message {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<Message, Id, Id> { return Property<Message, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .role.startsWith("X") }

    internal static var role: Property<Message, String, Void> { return Property<Message, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .category.startsWith("X") }

    internal static var category: Property<Message, String, Void> { return Property<Message, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .content.startsWith("X") }

    internal static var content: Property<Message, String, Void> { return Property<Message, String, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .timestamp > 1234 }

    internal static var timestamp: Property<Message, Date, Void> { return Property<Message, Date, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Use `.segments` to refer to this ToMany relation property in queries, like when using
    /// `QueryBuilder.and(property:, conditions:)`.

    internal static var segments: ToManyProperty<MessageSegment> { return ToManyProperty(.valuePropertyId(7)) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `Message.EntityBindingType`.
internal class MessageBinding: ObjectBox.EntityBinding {
    internal typealias EntityType = Message
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_role = propertyCollector.prepare(string: entity.role.rawValue)
        let propertyOffset_category = propertyCollector.prepare(string: entity.category.rawValue)
        let propertyOffset_content = propertyCollector.prepare(string: entity.content)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.timestamp, at: 2 + 2 * 5)
        propertyCollector.collect(dataOffset: propertyOffset_role, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_category, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_content, at: 2 + 2 * 4)
    }

    internal func postPut(fromEntity entity: EntityType, id: ObjectBox.Id, store: ObjectBox.Store) throws {
        if entityId(of: entity) == 0 {  // New object was put? Attach relations now that we have an ID.
            let segments = ToMany<MessageSegment>.backlink(
                sourceBox: store.box(for: ToMany<MessageSegment>.ReferencedType.self),
                sourceProperty: ToMany<MessageSegment>.ReferencedType.parentMessage,
                targetId: EntityId<Message>(id.value))
            if !entity.segments.isEmpty {
                segments.replace(entity.segments)
            }
            entity.segments = segments
            try entity.segments.applyToDb()
        }
    }
    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = Message()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.role = optConstruct(MessageRole.self, rawValue: entityReader.read(at: 2 + 2 * 2)) ?? .user
        entity.category = optConstruct(MessageCategory.self, rawValue: entityReader.read(at: 2 + 2 * 3)) ?? .chat
        entity.content = entityReader.read(at: 2 + 2 * 4)
        entity.timestamp = entityReader.read(at: 2 + 2 * 5)

        entity.segments = ToMany<MessageSegment>.backlink(
            sourceBox: store.box(for: ToMany<MessageSegment>.ReferencedType.self),
            sourceProperty: ToMany<MessageSegment>.ReferencedType.parentMessage,
            targetId: EntityId<Message>(entity.id.value))
        return entity
    }
}



extension MessageSegment: ObjectBox.__EntityRelatable {
    internal typealias EntityType = MessageSegment

    internal var _id: EntityId<MessageSegment> {
        return EntityId<MessageSegment>(self.id.value)
    }
}

extension MessageSegment: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = MessageSegmentBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static var entityInfo = ObjectBox.EntityInfo(name: "MessageSegment", id: 2)

    internal static var entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: MessageSegment.self, id: 2, uid: 7381594294969394688)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 3426147468643141632)
        try entityBuilder.addProperty(name: "category", type: PropertyType.string, id: 2, uid: 9201054686191175936)
        try entityBuilder.addProperty(name: "content", type: PropertyType.string, id: 3, uid: 7700704624860101376)
        try entityBuilder.addProperty(name: "position", type: PropertyType.long, id: 4, uid: 5453624712666520576)
        try entityBuilder.addProperty(name: "createdAt", type: PropertyType.date, id: 5, uid: 4772110707277018624)
        try entityBuilder.addProperty(name: "embedding", type: PropertyType.floatVector, flags: [.indexed], id: 6, uid: 5379588099506419712, indexId: 1, indexUid: 4222653835946004224)
            .hnswParams(dimensions: 100, neighborsPerNode: 64, indexingSearchCount: 400, flags: nil, distanceType: HnswDistanceType.cosine, reparationBacklinkProbability: nil, vectorCacheHintSizeKB: nil)
        try entityBuilder.addToOneRelation(name: "parentMessage", targetEntityInfo: ToOne<Message>.Target.entityInfo, flags: [.indexed, .indexPartialSkipZero], id: 7, uid: 8986195772624444672, indexId: 2, indexUid: 2345013675136534784)

        try entityBuilder.lastProperty(id: 7, uid: 8986195772624444672)
    }
}

extension MessageSegment {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MessageSegment.id == myId }
    internal static var id: Property<MessageSegment, Id, Id> { return Property<MessageSegment, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MessageSegment.category.startsWith("X") }
    internal static var category: Property<MessageSegment, String, Void> { return Property<MessageSegment, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MessageSegment.content.startsWith("X") }
    internal static var content: Property<MessageSegment, String, Void> { return Property<MessageSegment, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MessageSegment.position > 1234 }
    internal static var position: Property<MessageSegment, Int, Void> { return Property<MessageSegment, Int, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MessageSegment.createdAt > 1234 }
    internal static var createdAt: Property<MessageSegment, Date, Void> { return Property<MessageSegment, Date, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MessageSegment.embedding.isNotNil() }
    internal static var embedding: Property<MessageSegment, HnswIndexPropertyType, Void> { return Property<MessageSegment, HnswIndexPropertyType, Void>(propertyId: 6, isPrimaryKey: false) }
    internal static var parentMessage: Property<MessageSegment, EntityId<ToOne<Message>.Target>, ToOne<Message>.Target> { return Property(propertyId: 7) }


    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == MessageSegment {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<MessageSegment, Id, Id> { return Property<MessageSegment, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .category.startsWith("X") }

    internal static var category: Property<MessageSegment, String, Void> { return Property<MessageSegment, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .content.startsWith("X") }

    internal static var content: Property<MessageSegment, String, Void> { return Property<MessageSegment, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .position > 1234 }

    internal static var position: Property<MessageSegment, Int, Void> { return Property<MessageSegment, Int, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .createdAt > 1234 }

    internal static var createdAt: Property<MessageSegment, Date, Void> { return Property<MessageSegment, Date, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .embedding.isNotNil() }

    internal static var embedding: Property<MessageSegment, HnswIndexPropertyType, Void> { return Property<MessageSegment, HnswIndexPropertyType, Void>(propertyId: 6, isPrimaryKey: false) }

    internal static var parentMessage: Property<MessageSegment, ToOne<Message>.Target.EntityBindingType.IdType, ToOne<Message>.Target> { return Property<MessageSegment, ToOne<Message>.Target.EntityBindingType.IdType, ToOne<Message>.Target>(propertyId: 7) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `MessageSegment.EntityBindingType`.
internal class MessageSegmentBinding: ObjectBox.EntityBinding {
    internal typealias EntityType = MessageSegment
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_category = propertyCollector.prepare(string: entity.category.rawValue)
        let propertyOffset_content = propertyCollector.prepare(string: entity.content)
        let propertyOffset_embedding = propertyCollector.prepare(values: entity.embedding)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.position, at: 2 + 2 * 4)
        propertyCollector.collect(entity.createdAt, at: 2 + 2 * 5)
        try propertyCollector.collect(entity.parentMessage, at: 2 + 2 * 7, store: store)
        propertyCollector.collect(dataOffset: propertyOffset_category, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_content, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_embedding, at: 2 + 2 * 6)
    }

    internal func postPut(fromEntity entity: EntityType, id: ObjectBox.Id, store: ObjectBox.Store) throws {
        if entityId(of: entity) == 0 {  // New object was put? Attach relations now that we have an ID.
            entity.parentMessage.attach(to: store.box(for: Message.self))
        }
    }
    internal func setToOneRelation(_ propertyId: obx_schema_id, of entity: EntityType, to entityId: ObjectBox.Id?) {
        switch propertyId {
            case 7:
                entity.parentMessage.targetId = (entityId != nil) ? EntityId<Message>(entityId!) : nil
            default:
                fatalError("Attempt to change nonexistent ToOne relation with ID \(propertyId)")
        }
    }
    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = MessageSegment()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.category = optConstruct(MessageCategory.self, rawValue: entityReader.read(at: 2 + 2 * 2)) ?? .chat
        entity.content = entityReader.read(at: 2 + 2 * 3)
        entity.position = entityReader.read(at: 2 + 2 * 4)
        entity.createdAt = entityReader.read(at: 2 + 2 * 5)
        entity.embedding = entityReader.read(at: 2 + 2 * 6)

        entity.parentMessage = entityReader.read(at: 2 + 2 * 7, store: store)
        return entity
    }
}


/// Helper function that allows calling Enum(rawValue: value) with a nil value, which will return nil.
fileprivate func optConstruct<T: RawRepresentable>(_ type: T.Type, rawValue: T.RawValue?) -> T? {
    guard let rawValue = rawValue else { return nil }
    return T(rawValue: rawValue)
}

// MARK: - Store setup

fileprivate func cModel() throws -> OpaquePointer {
    let modelBuilder = try ObjectBox.ModelBuilder()
    try Message.buildEntity(modelBuilder: modelBuilder)
    try MessageSegment.buildEntity(modelBuilder: modelBuilder)
    modelBuilder.lastEntity(id: 2, uid: 7381594294969394688)
    modelBuilder.lastIndex(id: 2, uid: 2345013675136534784)
    return modelBuilder.finish()
}

extension ObjectBox.Store {
    /// A store with a fully configured model. Created by the code generator with your model's metadata in place.
    ///
    /// # In-memory database
    /// To use a file-less in-memory database, instead of a directory path pass `memory:` 
    /// together with an identifier string:
    /// ```swift
    /// let inMemoryStore = try Store(directoryPath: "memory:test-db")
    /// ```
    ///
    /// - Parameters:
    ///   - directoryPath: The directory path in which ObjectBox places its database files for this store,
    ///     or to use an in-memory database `memory:<identifier>`.
    ///   - maxDbSizeInKByte: Limit of on-disk space for the database files. Default is `1024 * 1024` (1 GiB).
    ///   - fileMode: UNIX-style bit mask used for the database files; default is `0o644`.
    ///     Note: directories become searchable if the "read" or "write" permission is set (e.g. 0640 becomes 0750).
    ///   - maxReaders: The maximum number of readers.
    ///     "Readers" are a finite resource for which we need to define a maximum number upfront.
    ///     The default value is enough for most apps and usually you can ignore it completely.
    ///     However, if you get the maxReadersExceeded error, you should verify your
    ///     threading. For each thread, ObjectBox uses multiple readers. Their number (per thread) depends
    ///     on number of types, relations, and usage patterns. Thus, if you are working with many threads
    ///     (e.g. in a server-like scenario), it can make sense to increase the maximum number of readers.
    ///     Note: The internal default is currently around 120. So when hitting this limit, try values around 200-500.
    ///   - readOnly: Opens the database in read-only mode, i.e. not allowing write transactions.
    ///
    /// - important: This initializer is created by the code generator. If you only see the internal `init(model:...)`
    ///              initializer, trigger code generation by building your project.
    internal convenience init(directoryPath: String, maxDbSizeInKByte: UInt64 = 1024 * 1024,
                            fileMode: UInt32 = 0o644, maxReaders: UInt32 = 0, readOnly: Bool = false) throws {
        try self.init(
            model: try cModel(),
            directory: directoryPath,
            maxDbSizeInKByte: maxDbSizeInKByte,
            fileMode: fileMode,
            maxReaders: maxReaders,
            readOnly: readOnly)
    }
}

// swiftlint:enable all
