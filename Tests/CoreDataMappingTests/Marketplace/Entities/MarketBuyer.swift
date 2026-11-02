import CoreData
import CoreDataMapping

@objc(MarketBuyer)
final class MarketBuyer: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var orders: NSSet?
    @NSManaged var reviews: NSSet?
}

nonisolated extension MarketBuyer {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketBuyer", attributeName: "id", keyPath: \MarketBuyer.id)
}
