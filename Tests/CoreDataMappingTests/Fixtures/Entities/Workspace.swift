import CoreData
import CoreDataMapping

@objc(Workspace)
final class Workspace: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var sections: NSOrderedSet?
    @NSManaged var resources: NSSet?
}

nonisolated extension Workspace {
    static let identity = CoreDataEntityIdentity(
        entityName: "Workspace", attributeName: "id", keyPath: \Workspace.id
    )
}
