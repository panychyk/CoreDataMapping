import CoreData
import CoreDataMapping

@objc(MarketOrder)
final class MarketOrder: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var status: String?
    @NSManaged var buyer: MarketBuyer?
    @NSManaged var items: NSOrderedSet?
    @NSManaged var payments: NSSet?
    @NSManaged var shipments: NSSet?
}

nonisolated extension MarketOrder {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketOrder", attributeName: "id", keyPath: \MarketOrder.id)
}
