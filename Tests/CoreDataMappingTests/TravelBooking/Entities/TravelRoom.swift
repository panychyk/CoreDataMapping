import CoreData
import CoreDataMapping

@objc(TravelRoom)
final class TravelRoom: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var number: String?
    @NSManaged var hotel: TravelHotel?
    @NSManaged var bookings: NSSet?
}

nonisolated extension TravelRoom {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelRoom", attributeName: "id", keyPath: \TravelRoom.id)
}
