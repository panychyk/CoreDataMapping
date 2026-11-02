import CoreData
import CoreDataMapping

@objc(TravelLoyalty)
final class TravelLoyalty: NSManagedObject {
    @NSManaged var id: Int64
    @NSManaged var name: String?
    @NSManaged var travelers: NSSet?
}

nonisolated extension TravelLoyalty {
    static let identity = CoreDataEntityIdentity(
        entityName: "TravelLoyalty", attributeName: "id", keyPath: \TravelLoyalty.id)
}
