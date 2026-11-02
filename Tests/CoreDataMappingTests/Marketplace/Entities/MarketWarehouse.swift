import CoreData
import CoreDataMapping

@objc(MarketWarehouse)
final class MarketWarehouse: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var stocks: NSSet?
    @NSManaged var shipments: NSSet?
}

nonisolated extension MarketWarehouse {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketWarehouse", attributeName: "id", keyPath: \MarketWarehouse.id)
}
