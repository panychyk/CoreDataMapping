import CoreData
import CoreDataMapping

@objc(Resource)
final class Resource: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var label: String?
    @NSManaged var documents: NSSet?
    @NSManaged var folders: NSSet?
    @NSManaged var dashboards: NSSet?
    @NSManaged var boards: NSSet?
    @NSManaged var workspaces: NSSet?
}

nonisolated extension Resource {
    static let identity = CoreDataEntityIdentity(
        entityName: "Resource", attributeName: "id", keyPath: \Resource.id
    )
}
