import CoreData
import CoreDataMapping

nonisolated enum ProgramMappingError: Error, Equatable {
    case missingTrack(Int)
    case missingCachedItem(Int)
    case duplicateReservationEvent(Int)
    case invalidEventType(String)
    case invalidPartnerType(String)
}

nonisolated enum ProgramSnapshots {
    static func latest<DTO, Id: Hashable>(
        _ dtos: [DTO], id: KeyPath<DTO, Id>
    ) -> [DTO] {
        var seen: Set<Id> = []
        return Array(dtos.reversed().filter {
            seen.insert($0[keyPath: id]).inserted
        }.reversed())
    }
}

/// Resolves every shared identity once for a root batch, before relationships are mapped.
nonisolated struct ProgramDependencies {
    let tracks: [Int: TrackEntity]
    let facilitators: [Int: FacilitatorEntity]
    let locations: [String: RealLocationEntity]

    init(
        trackReferences: [TrackReferenceDTO],
        facilitatorDTOs: [FacilitatorDTO],
        locationDTOs: [RealLocationDTO],
        using storage: CoreDataStorage
    ) throws {
        let trackIds = trackReferences.map(\.SeminarTrackID)
        tracks = try storage.existing(ids: trackIds, identifiedBy: TrackEntity.identity)
        for id in trackIds where tracks[id] == nil {
            throw ProgramMappingError.missingTrack(id)
        }

        facilitators = try storage.upsert(
            facilitatorDTOs,
            id: \FacilitatorDTO.FacilitatorID,
            identifiedBy: FacilitatorEntity.identity
        ) { entity, dto in
            entity.ordinal = dto.Ordinal
            entity.prefix = dto.Prefix
            entity.firstName = dto.FirstName
            entity.lastName = dto.LastName
            entity.fullName = dto.FullName
            entity.title = dto.Title
            entity.company = dto.Company
            entity.sourceUserId = dto.SourceUserID.map(NSNumber.init(value:))
            entity.iconPath = dto.IconPath
            entity.website = dto.Website
            entity.facebookUrl = dto.FacebookUrl
            entity.twitterUrl = dto.TwitterUrl
            entity.linkedInUrl = dto.LinkedInUrl
            entity.instagramUrl = dto.InstagramUrl
        }

        locations = try storage.upsert(
            locationDTOs,
            id: \RealLocationDTO.RealLocationID,
            identifiedBy: RealLocationEntity.identity
        ) { entity, dto in
            entity.name = dto.Name
            entity.address = dto.Address
            entity.latitude = dto.Lat
            entity.longitude = dto.Lng
        }
    }

    func trackEntities(_ dtos: [TrackReferenceDTO]?) -> [TrackEntity] {
        (dtos ?? []).map { tracks[$0.SeminarTrackID]! }
    }

    func facilitatorEntities(_ dtos: [FacilitatorDTO]?) -> [FacilitatorEntity] {
        (dtos ?? []).map { facilitators[$0.FacilitatorID]! }
    }

    func locationEntity(_ dto: RealLocationDTO?) -> RealLocationEntity? {
        dto.flatMap { locations[$0.RealLocationID] }
    }
}

nonisolated enum ProgramProjection {
    static func track(_ entity: TrackEntity) -> Track {
        Track(
            id: entity.id,
            categoryId: entity.categoryId?.intValue,
            name: entity.name,
            color: entity.color
        )
    }

    static func facilitator(_ entity: FacilitatorEntity) -> Facilitator {
        Facilitator(
            id: entity.id,
            ordinal: entity.ordinal,
            fullName: entity.fullName,
            title: entity.title,
            company: entity.company,
            sourceUserId: entity.sourceUserId?.intValue
        )
    }

    static func location(_ entity: RealLocationEntity?) -> RealLocation? {
        entity.map {
            RealLocation(
                id: $0.id,
                name: $0.name,
                address: $0.address,
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }

    static func customFields(_ entities: NSOrderedSet?) throws -> [CustomField] {
        try CoreDataStorage.ordered(entities, as: CustomFieldEntity.self)
            .map(CustomFieldEntityMapper().map)
    }
}
