import CoreData
import CoreDataMapping

@objc(Document)
final class Document: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var sections: NSOrderedSet?
    @NSManaged var resources: NSOrderedSet?
}

nonisolated extension Document {
    static let identity = CoreDataEntityIdentity(
        entityName: "Document", attributeName: "id", keyPath: \Document.id
    )
}
