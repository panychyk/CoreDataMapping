import CoreData
import CoreDataMapping

nonisolated struct ProgramRepositoryImpl: ProgramRepository {
    private let apiClient: any APIClient
    private let importer: CoreDataImporter

    init(apiClient: any APIClient, importer: CoreDataImporter) {
        self.apiClient = apiClient
        self.importer = importer
    }

    func getTracks() async throws -> [Track] {
        let response = try await apiClient.get(TracksResponseDTO.self, request: .tracks)
        let mapper = TrackEntityMapper()
        let snapshots = mapper.latestSnapshots(in: response.ReturnValue.Items)
        try await importer.write(snapshots) { batch, storage in
            try mapper.upsert(batch, using: storage)
        }
        return try await importer.read(
            response.ReturnValue.Items.map(\.SeminarTrackID)
        ) { ids, storage in
            let entities = try storage.existing(ids: ids, identifiedBy: TrackEntity.identity)
            return try ids.map { id in
                guard let entity = entities[id] else {
                    throw ProgramMappingError.missingCachedItem(id)
                }
                return ProgramProjection.track(entity)
            }
        }
    }

    func getSchedule() async throws -> [ScheduleEvent] {
        // Track references in a schedule must resolve to an existing global row.
        _ = try await getTracks()
        let response = try await apiClient.get(ScheduleResponseDTO.self, request: .schedule)
        let dtos = response.ReturnValue.Events.map(\.Event)
        let reservationsByEvent = Dictionary(
            grouping: response.ReturnValue.Reservations, by: \.EventID
        )
        let mapper = ScheduleEntityMapper()
        try await importer.write(mapper.latestSnapshots(in: dtos)) { batch, storage in
            try mapper.upsert(
                batch,
                reservations: batch.flatMap { reservationsByEvent[$0.EventID] ?? [] },
                using: storage
            )
        }
        return try await importer.read(dtos.map(\.UniqueID)) { ids, storage in
            let customFields = #keyPath(ScheduleEventEntity.customFields)
            let entities = try storage.existing(
                ids: ids,
                identifiedBy: ScheduleEventEntity.identity,
                prefetching: [
                    #keyPath(ScheduleEventEntity.tracks),
                    #keyPath(ScheduleEventEntity.facilitators),
                    #keyPath(ScheduleEventEntity.realLocation),
                    #keyPath(ScheduleEventEntity.reservation),
                    customFields,
                    "\(customFields).\(#keyPath(CustomFieldEntity.multipleValues))"
                ]
            )
            return try ids.map { id in
                guard let entity = entities[id] else {
                    throw ProgramMappingError.missingCachedItem(id)
                }
                return try mapper.map(entity)
            }
        }
    }

    func getElectives() async throws -> [Elective] {
        // Electives are committed only after Tracks have been imported.
        _ = try await getTracks()
        let response = try await apiClient.get(ElectivesResponseDTO.self, request: .electives)
        let dtos = response.ReturnValue.Items
        let mapper = ElectiveEntityMapper()
        try await importer.write(mapper.latestSnapshots(in: dtos)) { batch, storage in
            try mapper.upsert(batch, using: storage)
        }
        return try await importer.read(dtos.map(\.EventID)) { ids, storage in
            let customFields = #keyPath(ElectiveEntity.customFields)
            let entities = try storage.existing(
                ids: ids,
                identifiedBy: ElectiveEntity.identity,
                prefetching: [
                    #keyPath(ElectiveEntity.tracks),
                    #keyPath(ElectiveEntity.facilitators),
                    #keyPath(ElectiveEntity.realLocation),
                    customFields,
                    "\(customFields).\(#keyPath(CustomFieldEntity.multipleValues))"
                ]
            )
            return try ids.map { id in
                guard let entity = entities[id] else {
                    throw ProgramMappingError.missingCachedItem(id)
                }
                return try mapper.map(entity)
            }
        }
    }
}
