import CoreData
import CoreDataMapping

@objc(Board)
final class Board: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var sections: NSOrderedSet?
    @NSManaged var resources: NSOrderedSet?
}

nonisolated extension Board {
    static let identity = CoreDataEntityIdentity(
        entityName: "Board", attributeName: "id", keyPath: \Board.id
    )
}
