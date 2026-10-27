import CoreData
import CoreDataMapping

@objc(ScheduleEventEntity)
nonisolated final class ScheduleEventEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var eventId: Int
    @NSManaged var seminarId: Int
    @NSManaged var eventType: String
    @NSManaged var name: String?
    @NSManaged var detail: String?
    @NSManaged var startDate: Date?
    @NSManaged var endDate: Date?
    @NSManaged var location: String?
    @NSManaged var ordinal: Int
    @NSManaged var acceptStatus: String?
    @NSManaged var acceptStatusId: NSNumber?
    @NSManaged var allDayEvent: NSNumber?
    @NSManaged var allowVotesForQuestions: NSNumber?
    @NSManaged var analyticDashboardAvailable: NSNumber?
    @NSManaged var attendeeStatus: String?
    @NSManaged var disableChat: NSNumber?
    @NSManaged var endDateTimeLocal: String?
    @NSManaged var eventIpadDetailImageUrl: String?
    @NSManaged var eventIphoneMediumImageUrl: String?
    @NSManaged var externalEngagementJSON: Data?
    @NSManaged var featuredVideoJSON: Data?
    @NSManaged var hasSponsorRepresentativeRequest: NSNumber?
    @NSManaged var insightsCount: NSNumber?
    @NSManaged var isBreakout: NSNumber?
    @NSManaged var isElective: NSNumber?
    @NSManaged var isSplit: NSNumber?
    @NSManaged var isTeleconferencePresentation: NSNumber?
    @NSManaged var isUserInSeatsList: NSNumber?
    @NSManaged var lastModifiedUserId: NSNumber?
    @NSManaged var locationDataJSON: Data?
    @NSManaged var locationOnIphoneImageUrl: String?
    @NSManaged var mapItemJSON: Data?
    @NSManaged var maximumNumberOfRegistrants: NSNumber?
    @NSManaged var originName: String?
    @NSManaged var postSubTitleJSON: Data?
    @NSManaged var roomJSON: Data?
    @NSManaged var sectionsJSON: Data?
    @NSManaged var showTimeAsAvailable: NSNumber?
    @NSManaged var speakers: String?
    @NSManaged var startDateTimeLocal: String?
    @NSManaged var startedSeminarPresentationUniqueIdJSON: Data?
    @NSManaged var subtitle: String?
    @NSManaged var supportAskQuestion: NSNumber?
    @NSManaged var supportWaitingQueue: NSNumber?
    @NSManaged var teleconferenceDetails: String?
    @NSManaged var teleconferenceType: String?
    @NSManaged var teleconferenceUrl: String?
    @NSManaged var teleconferenceUrlTypeJSON: Data?
    @NSManaged var timeZoneAbbr: String?
    @NSManaged var timeZoneId: String?
    @NSManaged var timeZoneOffsetMinutes: NSNumber?
    @NSManaged var visibleForAllUsers: NSNumber?
    @NSManaged var tracks: NSOrderedSet?
    @NSManaged var facilitators: NSOrderedSet?
    @NSManaged var realLocation: RealLocationEntity?
    @NSManaged var customFields: NSOrderedSet?
    @NSManaged var reservation: ScheduleReservationEntity?
}

nonisolated extension ScheduleEventEntity {
    static let identity = CoreDataEntityIdentity(
        entityName: "ScheduleEventEntity",
        attributeName: #keyPath(ScheduleEventEntity.id),
        keyPath: \ScheduleEventEntity.id
    )
}
