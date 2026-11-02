import CoreData
import CoreDataMapping

@objc(MarketStock)
final class MarketStock: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var quantity: Int64
    @NSManaged var product: MarketProduct?
    @NSManaged var warehouse: MarketWarehouse?
}

nonisolated extension MarketStock {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketStock", attributeName: "id", keyPath: \MarketStock.id)
}
