import CoreData
import CoreDataMapping

@objc(ElectiveEntity)
nonisolated final class ElectiveEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var name: String?
    @NSManaged var detail: String?
    @NSManaged var subtitle: String?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var location: String?
    @NSManaged var ordinal: Int
    @NSManaged var analyticDashboardAvailable: NSNumber?
    @NSManaged var disableChat: NSNumber?
    @NSManaged var endDateTimeLocal: String?
    @NSManaged var eventIpadDetailImageUrl: String?
    @NSManaged var eventIphoneMediumImageUrl: String?
    @NSManaged var insightsCount: NSNumber?
    @NSManaged var isUserInSeatsList: NSNumber?
    @NSManaged var isUserInWaitingList: NSNumber?
    @NSManaged var maximumNumberOfRegistrants: NSNumber?
    @NSManaged var seatsLeftCount: NSNumber?
    @NSManaged var startDateTimeLocal: String?
    @NSManaged var supportAskQuestion: NSNumber?
    @NSManaged var supportWaitingQueue: NSNumber?
    @NSManaged var teleconferenceDetails: String?
    @NSManaged var teleconferenceType: String?
    @NSManaged var teleconferenceUrl: String?
    @NSManaged var usersCount: NSNumber?
    @NSManaged var waitingCount: NSNumber?
    @NSManaged var tracks: NSOrderedSet?
    @NSManaged var facilitators: NSOrderedSet?
    @NSManaged var realLocation: RealLocationEntity?
    @NSManaged var customFields: NSOrderedSet?
}

nonisolated extension ElectiveEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "ElectiveEntity",
        attributeName: #keyPath(ElectiveEntity.id),
        keyPath: \ElectiveEntity.id
    )
}
