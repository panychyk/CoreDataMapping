import CoreData
import CoreDataMapping

@objc(MarketReview)
final class MarketReview: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var rating: Int64
    @NSManaged var buyer: MarketBuyer?
    @NSManaged var product: MarketProduct?
}

nonisolated extension MarketReview {
    static let identity = CoreDataEntityIdentity(
        entityName: "MarketReview", attributeName: "id", keyPath: \MarketReview.id)
}
