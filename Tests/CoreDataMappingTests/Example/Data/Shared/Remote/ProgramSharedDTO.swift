import Foundation

nonisolated struct TrackReferenceDTO: Decodable, Sendable {
    let SeminarTrackID: Int
    var SeminarTrackCategoryID: Int? = nil
    var Name: String? = nil
    var Color: String? = nil
}

nonisolated struct FacilitatorDTO: Decodable, Sendable {
    let FacilitatorID: Int
    let Ordinal: Int
    let Prefix: String?
    let FirstName: String?
    let LastName: String?
    let FullName: String?
    let Title: String?
    let Company: String?
    let SourceUserID: Int?
    let IconPath: String?
    let Website: String?
    let FacebookUrl: String?
    let TwitterUrl: String?
    let LinkedInUrl: String?
    let InstagramUrl: String?
}
