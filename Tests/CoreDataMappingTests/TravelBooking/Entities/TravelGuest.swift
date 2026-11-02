import CoreData

@objc(TravelGuest)
final class TravelGuest: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var name: String?
    @NSManaged var booking: TravelBooking?
    @NSManaged var traveler: TravelTraveler?
    @NSManaged var tickets: NSSet?
}
