import CoreData
import CoreDataMapping

@objc(MarketCategory)
final class MarketCategory: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var products: NSSet?
}

nonisolated extension MarketCategory {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketCategory", attributeName: "id", keyPath: \MarketCategory.id)
}
