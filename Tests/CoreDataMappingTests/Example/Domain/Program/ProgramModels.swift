import Foundation

nonisolated struct Track: Identifiable, Sendable, Equatable {
    let id: Int
    let categoryId: Int?
    let name: String?
    let color: String?
}

nonisolated struct Facilitator: Identifiable, Sendable, Equatable {
    let id: Int
    let ordinal: Int
    let fullName: String?
    let title: String?
    let company: String?
    let sourceUserId: Int?
}

nonisolated enum ScheduleEventType: String, Sendable, Equatable {
    case event
    case roomReservation
}

nonisolated struct ScheduleEvent: Identifiable, Sendable, Equatable {
    let id: Int
    let eventId: Int
    let seminarId: Int
    let eventType: ScheduleEventType
    let name: String?
    let startDate: Date?
    let endDate: Date?
    let tracks: [Track]
    let facilitators: [Facilitator]
    let realLocation: RealLocation?
    let customFields: [CustomField]
    let reservation: ScheduleReservation?
}

nonisolated enum ScheduleReservationPartnerType: String, Sendable, Equatable {
    case notSet
    case master
    case child
}

nonisolated struct ScheduleReservation: Identifiable, Sendable, Equatable {
    let id: Int
    let ownerUserId: Int?
    let attendeesCount: Int
    let userAttendeeRequired: Bool
    let partnerType: ScheduleReservationPartnerType
}

nonisolated struct Elective: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String?
    let startDate: Date?
    let endDate: Date?
    let tracks: [Track]
    let facilitators: [Facilitator]
    let realLocation: RealLocation?
    let customFields: [CustomField]
}
