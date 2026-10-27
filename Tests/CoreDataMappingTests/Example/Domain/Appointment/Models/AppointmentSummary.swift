import Foundation

nonisolated struct AppointmentSummary: Identifiable, Sendable, Equatable {
    let id: Int
    let startDate: Date?
    let endDate: Date?
    let name: String
    let isDraft: Bool
    let status: AppointmentStatus
    let topics: [ReservationTopic]?
    let realLocation: RealLocation?
    let customFields: [CustomField]?

    init(
        id: Int,
        startDate: Date?,
        endDate: Date?,
        name: String,
        isDraft: Bool,
        status: AppointmentStatus,
        topics: [ReservationTopic]? = nil,
        realLocation: RealLocation? = nil,
        customFields: [CustomField]? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.name = name
        self.isDraft = isDraft
        self.status = status
        self.topics = topics
        self.realLocation = realLocation
        self.customFields = customFields
    }
}
