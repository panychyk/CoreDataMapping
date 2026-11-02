import CoreData
import CoreDataMapping

@objc(MarketOrderItem)
final class MarketOrderItem: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var quantity: Int64
    @NSManaged var order: MarketOrder?
    @NSManaged var product: MarketProduct?
}
