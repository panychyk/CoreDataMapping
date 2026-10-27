nonisolated enum EventType: String, Decodable, Sendable {
    case Event
    case RoomReservation
}

nonisolated enum HomeSectionType: String, Decodable, Sendable {
    case Materials
    case TileVideo
    case TileSystemRecentFeed
    case TileSystemHappeningNow
    case TileImageDeepLink
    case TileImageContent
    case CompanyTileSystemRecentFeed
    case CompanyTileSystemHappeningNow
    case EventInstanceByTrack
    case TileText
    case TileSystemTravel
    case CompanyTileSystemTravel
}

nonisolated enum HomeSectionTileSizeType: String, Decodable, Sendable {
    case SmallTile
    case LargeTile
}

nonisolated enum HomeSectionLinkToType: String, Decodable, Sendable {
    case User
    case Facilitator
    case Event
    case SeminarLocation
    case Sponsor
}

nonisolated enum RoomReservationAttendeeStatus: String, Decodable, Sendable {
    case Pending
    case Declined
    case Maybe
    case Accepted
    case Attended
}

nonisolated enum TeleconferenceEntityType: String, Decodable, Sendable {
    case Disabled
    case Manual
    case Default
    case ZoomPersonal
    case WebEx
    case SeminarPresentation
    case Zoom
    case MSTeams
    case Agora
}

nonisolated enum AcceptStatusType: String, Decodable, Sendable {
    case Unknown
    case Accepted
    case Declined
}

nonisolated enum CustomFieldEntityType: String, Decodable, Sendable {
    case UserUser
    case UserCustomer
    case CompanyCustomer
}

nonisolated enum RoomReservationUserPartnerType: String, Decodable, Sendable {
    case NotSet
    case Master
    case Child
}

nonisolated enum RoomReservationParticipationStatusType: String, Decodable, Sendable {
    case NotSet
    case Participated
    case NoShow
}

nonisolated enum RoomReservationUserStatus: String, Decodable, Sendable {
    case Pending
    case Confirmed
    case Declined
    case Cancelled
    case Planned
}

nonisolated enum RoomReservationPriorityType: String, Decodable, Sendable {
    case Tier3
    case Tier2
    case Tier1
}

nonisolated enum UserAttendType: String, Decodable, Sendable {
    case Unknown
    case InPerson
    case Remote
}
