import CoreData
import CoreDataMapping

@objc(Folder)
final class Folder: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var sections: NSOrderedSet?
    @NSManaged var resources: NSSet?
}

nonisolated extension Folder {
    static let identity = CoreDataEntityIdentity(
        entityName: "Folder", attributeName: "id", keyPath: \Folder.id
    )
}
