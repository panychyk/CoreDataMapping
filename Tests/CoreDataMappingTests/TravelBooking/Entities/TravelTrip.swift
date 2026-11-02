import CoreData
import CoreDataMapping

@objc(TravelTrip)
final class TravelTrip: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var title: String?
    @NSManaged var traveler: TravelTraveler?
    @NSManaged var bookings: NSOrderedSet?
}

nonisolated extension TravelTrip {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelTrip", attributeName: "id", keyPath: \TravelTrip.id)
}
