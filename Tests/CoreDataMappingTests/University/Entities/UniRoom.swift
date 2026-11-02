import CoreData
import CoreDataMapping

@objc(UniRoom)
final class UniRoom: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var offerings: NSSet?
}

nonisolated extension UniRoom {
    static let identity = CoreDataEntityIdentity(
        entityName: "UniRoom", attributeName: "id", keyPath: \UniRoom.id)
}
