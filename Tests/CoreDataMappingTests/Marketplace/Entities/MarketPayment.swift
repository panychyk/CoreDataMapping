import CoreData
import CoreDataMapping

@objc(MarketPayment)
final class MarketPayment: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var amount: Int64
    @NSManaged var status: String?
    @NSManaged var order: MarketOrder?
}
