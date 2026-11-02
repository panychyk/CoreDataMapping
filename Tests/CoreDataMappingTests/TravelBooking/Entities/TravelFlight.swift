import CoreData
import CoreDataMapping

@objc(TravelFlight)
final class TravelFlight: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var code: String?
    @NSManaged var origin: TravelAirport?
    @NSManaged var destination: TravelAirport?
    @NSManaged var bookings: NSSet?
}

nonisolated extension TravelFlight {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelFlight", attributeName: "id", keyPath: \TravelFlight.id)
}
