import CoreData
import CoreDataMapping

@objc(TravelHotel)
final class TravelHotel: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var rooms: NSSet?
}

nonisolated extension TravelHotel {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelHotel", attributeName: "id", keyPath: \TravelHotel.id)
}
