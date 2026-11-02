import CoreData
import CoreDataMapping

@objc(TravelAirport)
final class TravelAirport: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var code: String?
    @NSManaged var departures: NSSet?
    @NSManaged var arrivals: NSSet?
}

nonisolated extension TravelAirport {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelAirport", attributeName: "id", keyPath: \TravelAirport.id)
}
