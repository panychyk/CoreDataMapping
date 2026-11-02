import CoreData
import CoreDataMapping

@objc(MarketSeller)
final class MarketSeller: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var products: NSSet?
}

nonisolated extension MarketSeller {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketSeller", attributeName: "id", keyPath: \MarketSeller.id)
}
