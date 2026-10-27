import Foundation

nonisolated struct AppointmentsResponseDTO: Decodable, Sendable {
    let Items: [AppointmentDTO]
}

nonisolated struct AppointmentDTO: Decodable, Sendable {
    let SeminarOpportunities: [SeminarOpportunityDTO]?
    let Attendees: [AttendeeDTO]?
    let CreatorUserID: Int
    let RoomIDs: [Int]
    let RoomNameOnRental: String?
    let RoomReservationUserID: Int
    let IsDraft: Bool
    let AppointmentName: String
    let StartDate: Date?
    let EndDate: Date?
    let StartDateUTC: Date?
    let EndDateUTC: Date?
    let SeminarID: Int
    let SeminarTimeZoneID: String?
    let SpecialInstructions: String?
    let DurationInMinutes: Int?
    let Status: RoomReservationUserStatus
    let Priority: RoomReservationPriorityType
    let MetadataDictionaryItems: [MetadataDictionaryItemDTO]
    let User: UserDTO
    let Topics: [ReservationTopicDTO]?
    let CustomRoomName: String?
    let RealLocation: RealLocationDTO
    let DisableSendInvitations: Bool
    let DisableSendUpdates: Bool
    let ReservationUrl: String?
    let AskCustomer: Bool
    let RegistrationEnabled: Bool
    let TeleconferenceUrl: String?
    let TeleconferenceDetails: String?
    let TeleconferenceType: TeleconferenceEntityType
    let StartedSeminarPresentationUniqueID: String?
    let RoomReservationImageUrl: String?
    let RoomReservationImageTabletUrl: String?
    let UserTeams: [Int]
    let FormatType: UserAttendType
    let ResourceEnabled: Bool
    let PartnerType: RoomReservationUserPartnerType
    let SegmentsCount: Int
    let CustomFields: [CustomFieldDTO]?
}

nonisolated struct SeminarOpportunityDTO: Decodable, Sendable {
    let SeminarOpportunityID: Int
    let Ordinal: Int
    let Name: String?
}

nonisolated struct AttendeeDTO: Decodable, Sendable {
    let UserID: Int
    let Status: RoomReservationAttendeeStatus
    let StatusUpdatedDateUTC: Date?
    let ParticipationStatus: RoomReservationParticipationStatusType
    let StateID: Int?
    let CountryID: Int?
    let IsCustomer: Bool
    let Duplicate: Bool
    let DraftSelectDateEmailOpened: Date?
    let InvitationEmailOpened: Date?
}

nonisolated struct MetadataDictionaryItemDTO: Decodable, Sendable {
    let MetadataDictionaryItemID: Int
}

nonisolated struct ReservationTopicDTO: Decodable, Sendable {
    let ReservationTopicID: Int
    let Name: String?
}

nonisolated struct RealLocationDTO: Decodable, Sendable {
    let RealLocationID: String
    let Name: String?
    let Address: String?
    let Lat: Double
    let Lng: Double
}
