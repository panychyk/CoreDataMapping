import CoreData

@objc(TravelTicket)
final class TravelTicket: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var seat: String?
    @NSManaged var booking: TravelBooking?
    @NSManaged var guest: TravelGuest?
}
