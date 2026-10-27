import Foundation

nonisolated struct ScheduleResponseDTO: Decodable, Sendable {
    let ReturnValue: SchedulePayloadDTO
}

nonisolated struct SchedulePayloadDTO: Decodable, Sendable {
    let Events: [ScheduleItemDTO]
    let Reservations: [ScheduleReservationDTO]
}

nonisolated struct ScheduleItemDTO: Decodable, Sendable {
    let Event: ScheduleEventDTO
}

nonisolated struct ScheduleEventDTO: Decodable, Sendable {
    let UniqueID: Int
    let EventID: Int
    let SeminarVersionID: Int
    let EntityEventType: EventType
    let Name: String?
    let Description: String?
    let StartDateTimeUTC: Date?
    let EndDateTimeUTC: Date?
    let Location: String?
    let Ordinal: Int
    let Tracks: [TrackReferenceDTO]?
    let Facilitators: [FacilitatorDTO]?
    let RealLocation: RealLocationDTO?
    let CustomFieldValues: [CustomFieldDTO]?
    var AcceptStatus: AcceptStatusType? = nil
    var AcceptStatusID: Int? = nil
    var AllDayEvent: Bool? = nil
    var AllowVotesForQuestions: Bool? = nil
    var AnalyticDashboardAvailable: Bool? = nil
    var AttendeeStatus: RoomReservationAttendeeStatus? = nil
    var DisableChat: Bool? = nil
    var EndDateTime: String? = nil
    var EventIpadDetailImageUrl: String? = nil
    var EventIphoneMediumImageUrl: String? = nil
    var ExternalEngagementID: ProgramJSONValue? = nil
    var FeaturedVideo: ProgramJSONValue? = nil
    var HasSponsorRepresentativeRequest: Bool? = nil
    var InsightsCount: Int? = nil
    var IsBreakout: Bool? = nil
    var IsElective: Bool? = nil
    var IsSplit: Bool? = nil
    var IsTeleconferencePresentation: Bool? = nil
    var IsUserInSeatsList: Bool? = nil
    var LastModifiedUserID: Int? = nil
    var LocationData: ProgramJSONValue? = nil
    var LocationOnIphoneImageUrl: String? = nil
    var MapItem: ProgramJSONValue? = nil
    var MaximumNumberOfRegistrants: Int? = nil
    var OriginName: String? = nil
    var PostSubTitle: ProgramJSONValue? = nil
    var Room: ProgramJSONValue? = nil
    var Sections: ProgramJSONValue? = nil
    var ShowTimeAsAvailable: Bool? = nil
    var Speakers: String? = nil
    var StartDateTime: String? = nil
    var StartedSeminarPresentationUniqueID: ProgramJSONValue? = nil
    var Subtitle: String? = nil
    var SupportAskQuestion: Bool? = nil
    var SupportWaitingQueue: Bool? = nil
    var TeleconferenceDetails: String? = nil
    var TeleconferenceType: TeleconferenceEntityType? = nil
    var TeleconferenceUrl: String? = nil
    var TeleconferenceUrlType: ProgramJSONValue? = nil
    var TimeZoneAbbr: String? = nil
    var TimeZoneID: String? = nil
    var TimeZoneOffsetMinutes: Int? = nil
    var VisibleForAllUsers: Bool? = nil
}

nonisolated struct ScheduleReservationDTO: Decodable, Sendable {
    let RoomReservationUserID: Int
    let EventID: Int
    let OwnerUser: UserDTO
    let AttendeesCount: Int
    let UserAttendeeRequired: Bool
    let PartnerType: RoomReservationUserPartnerType
}
