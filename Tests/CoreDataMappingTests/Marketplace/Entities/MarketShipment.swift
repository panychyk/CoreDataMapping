import CoreData
import CoreDataMapping

@objc(MarketShipment)
final class MarketShipment: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var tracking: String?
    @NSManaged var order: MarketOrder?
    @NSManaged var warehouse: MarketWarehouse?
}
