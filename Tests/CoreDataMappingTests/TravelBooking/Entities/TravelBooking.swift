import CoreData

@objc(TravelBooking)
final class TravelBooking: NSManagedObject {
    @NSManaged var localID: Int64
    @NSManaged var status: String?
    @NSManaged var kind: String?
    @NSManaged var trip: TravelTrip?
    @NSManaged var flight: TravelFlight?
    @NSManaged var room: TravelRoom?
    @NSManaged var guests: NSOrderedSet?
    @NSManaged var payments: NSOrderedSet?
    @NSManaged var tickets: NSOrderedSet?
}
