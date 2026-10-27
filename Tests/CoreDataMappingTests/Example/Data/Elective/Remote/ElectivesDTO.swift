import Foundation

nonisolated struct ElectivesResponseDTO: Decodable, Sendable {
    let ReturnValue: ElectivesPayloadDTO
}

nonisolated struct ElectivesPayloadDTO: Decodable, Sendable {
    let Items: [ElectiveDTO]
}

nonisolated struct ElectiveDTO: Decodable, Sendable {
    let EventID: Int
    let Name: String?
    let Description: String?
    let SubTitle: String?
    let StartDateTimeUTC: Date?
    let EndDateTimeUTC: Date?
    let Location: String?
    let Ordinal: Int
    let Tracks: [TrackReferenceDTO]?
    let Facilitators: [FacilitatorDTO]?
    let RealLocation: RealLocationDTO?
    let CustomFieldValues: [CustomFieldDTO]?
    var AnalyticDashboardAvailable: Bool? = nil
    var DisableChat: Bool? = nil
    var EndDateTime: String? = nil
    var EventIpadDetailImageUrl: String? = nil
    var EventIphoneMediumImageUrl: String? = nil
    var InsightsCount: Int? = nil
    var IsUserInSeatsList: Bool? = nil
    var IsUserInWaitingList: Bool? = nil
    var MaximumNumberOfRegistrants: Int? = nil
    var SeatsLeftCount: Int? = nil
    var StartDateTime: String? = nil
    var SupportAskQuestion: Bool? = nil
    var SupportWaitingQueue: Bool? = nil
    var TeleconferenceDetails: String? = nil
    var TeleconferenceType: TeleconferenceEntityType? = nil
    var TeleconferenceUrl: String? = nil
    var UsersCount: Int? = nil
    var WaitingCount: Int? = nil
}
