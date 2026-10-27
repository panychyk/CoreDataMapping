import CoreData
import CoreDataMapping

nonisolated struct AppointmentRepositoryImpl: AppointmentRepository {
    private let apiClient: any APIClient
    private let importer: CoreDataImporter
    private let entityMapper: AppointmentEntityMapper

    init(
        apiClient: any APIClient,
        importer: CoreDataImporter,
        entityMapper: AppointmentEntityMapper = AppointmentEntityMapper()
    ) {
        self.apiClient = apiClient
        self.importer = importer
        self.entityMapper = entityMapper
    }

    func getAppointmentsList(for seminarId: Int) async throws -> [AppointmentSummary] {
        let response = try await apiClient.get(
            AppointmentsResponseDTO.self,
            request: .appointments(seminarId: seminarId)
        )
        let dtos = response.Items.filter { $0.SeminarID == seminarId }

        // Resolve repeated roots across the whole response before commit batching.
        // Read results below still follow the original response order.
        let snapshots = entityMapper.latestSnapshots(in: dtos)
        try await importer.write(snapshots) { batch, storage in
            _ = try entityMapper.upsert(batch, using: storage)
        }

        let ids = dtos.map(\.RoomReservationUserID)
        return try await importer.read(ids) { ids, storage in
            let customFields = #keyPath(AppointmentEntity.customFields)
            let entities = try storage.existing(
                ids: ids,
                identifiedBy: AppointmentEntity.identity,
                prefetching: [
                    #keyPath(AppointmentEntity.topics),
                    #keyPath(AppointmentEntity.realLocation),
                    customFields,
                    "\(customFields).\(#keyPath(CustomFieldEntity.multipleValues))"
                ]
            )
            return try ids.map { id in
                guard let entity = entities[id] else {
                    throw AppointmentRepositoryError.missingCachedAppointment(id)
                }
                return try entityMapper.map(entity)
            }
        }
    }
}

nonisolated enum AppointmentRepositoryError: Error, Equatable {
    case missingCachedAppointment(Int)
}
