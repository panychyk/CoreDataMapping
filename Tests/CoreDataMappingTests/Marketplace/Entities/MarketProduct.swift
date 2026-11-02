import CoreData
import CoreDataMapping

@objc(MarketProduct)
final class MarketProduct: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var seller: MarketSeller?
    @NSManaged var categories: NSSet?
    @NSManaged var stocks: NSSet?
    @NSManaged var orderItems: NSSet?
    @NSManaged var reviews: NSSet?
}

nonisolated extension MarketProduct {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketProduct", attributeName: "id", keyPath: \MarketProduct.id)
}
