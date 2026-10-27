import Foundation

nonisolated struct TracksResponseDTO: Decodable, Sendable {
    let ReturnValue: TracksPayloadDTO
}

nonisolated struct TracksPayloadDTO: Decodable, Sendable {
    let Items: [TrackDTO]
}

nonisolated struct TrackDTO: Decodable, Sendable {
    let SeminarTrackID: Int
    let SeminarTrackCategoryID: Int?
    let Name: String?
    let Color: String?
}
