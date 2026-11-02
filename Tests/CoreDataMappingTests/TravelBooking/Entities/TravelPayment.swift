import CoreData

@objc(TravelPayment)
final class TravelPayment: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var amount: Int64
    @NSManaged var status: String?
    @NSManaged var booking: TravelBooking?
}
