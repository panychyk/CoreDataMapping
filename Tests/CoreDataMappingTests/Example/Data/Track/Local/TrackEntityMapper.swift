import CoreData
import CoreDataMapping

nonisolated struct TrackEntityMapper: Sendable {
    func latestSnapshots(in dtos: [TrackDTO]) -> [TrackDTO] {
        ProgramSnapshots.latest(dtos, id: \TrackDTO.SeminarTrackID)
    }

    func upsert(_ dtos: [TrackDTO], using storage: CoreDataStorage) throws {
        _ = try storage.upsert(
            dtos,
            id: \TrackDTO.SeminarTrackID,
            identifiedBy: TrackEntity.identity
        ) { entity, dto in
            entity.categoryId = dto.SeminarTrackCategoryID.map(NSNumber.init(value:))
            entity.name = dto.Name
            entity.color = dto.Color
        }
    }
}
