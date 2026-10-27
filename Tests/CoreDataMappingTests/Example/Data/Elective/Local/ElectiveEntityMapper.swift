import CoreData
import CoreDataMapping

nonisolated struct ElectiveEntityMapper: Sendable {
    func latestSnapshots(in dtos: [ElectiveDTO]) -> [ElectiveDTO] {
        ProgramSnapshots.latest(dtos, id: \ElectiveDTO.EventID)
    }

    func upsert(_ dtos: [ElectiveDTO], using storage: CoreDataStorage) throws {
        let snapshots = latestSnapshots(in: dtos)
        let customFields = #keyPath(ElectiveEntity.customFields)
        let electives = try storage.upsert(
            snapshots,
            id: \ElectiveDTO.EventID,
            identifiedBy: ElectiveEntity.identity,
            prefetching: [customFields, "\(customFields).\(#keyPath(CustomFieldEntity.multipleValues))"]
        ) { entity, dto in
            entity.name = dto.Name
            entity.detail = dto.Description
            entity.subtitle = dto.SubTitle
            entity.startDate = dto.StartDateTimeUTC
            entity.endDate = dto.EndDateTimeUTC
            entity.location = dto.Location
            entity.ordinal = dto.Ordinal
            entity.analyticDashboardAvailable = dto.AnalyticDashboardAvailable.map(NSNumber.init(value:))
            entity.disableChat = dto.DisableChat.map(NSNumber.init(value:))
            entity.endDateTimeLocal = dto.EndDateTime
            entity.eventIpadDetailImageUrl = dto.EventIpadDetailImageUrl
            entity.eventIphoneMediumImageUrl = dto.EventIphoneMediumImageUrl
            entity.insightsCount = dto.InsightsCount.map(NSNumber.init(value:))
            entity.isUserInSeatsList = dto.IsUserInSeatsList.map(NSNumber.init(value:))
            entity.isUserInWaitingList = dto.IsUserInWaitingList.map(NSNumber.init(value:))
            entity.maximumNumberOfRegistrants = dto.MaximumNumberOfRegistrants.map(NSNumber.init(value:))
            entity.seatsLeftCount = dto.SeatsLeftCount.map(NSNumber.init(value:))
            entity.startDateTimeLocal = dto.StartDateTime
            entity.supportAskQuestion = dto.SupportAskQuestion.map(NSNumber.init(value:))
            entity.supportWaitingQueue = dto.SupportWaitingQueue.map(NSNumber.init(value:))
            entity.teleconferenceDetails = dto.TeleconferenceDetails
            entity.teleconferenceType = dto.TeleconferenceType?.rawValue
            entity.teleconferenceUrl = dto.TeleconferenceUrl
            entity.usersCount = dto.UsersCount.map(NSNumber.init(value:))
            entity.waitingCount = dto.WaitingCount.map(NSNumber.init(value:))
        }
        let dependencies = try ProgramDependencies(
            trackReferences: snapshots.flatMap { $0.Tracks ?? [] },
            facilitatorDTOs: snapshots.flatMap { $0.Facilitators ?? [] },
            locationDTOs: snapshots.compactMap(\.RealLocation),
            using: storage
        )

        for dto in snapshots {
            let entity = electives[dto.EventID]!
            entity.tracks = try storage.replace(with: dependencies.trackEntities(dto.Tracks))
            entity.facilitators = try storage.replace(
                with: dependencies.facilitatorEntities(dto.Facilitators)
            )
            entity.realLocation = dependencies.locationEntity(dto.RealLocation)
            let current = try CoreDataStorage.ordered(entity.customFields, as: CustomFieldEntity.self)
            let fields = try storage.reconcileOwned(
                dto.CustomFieldValues ?? [],
                current: current,
                dtoId: \CustomFieldDTO.CustomFieldID,
                entityId: \CustomFieldEntity.id,
                create: { try storage.insert(CustomFieldEntity.self) }
            ) { field, fieldDTO in
                try CustomFieldEntityMapper().update(field, from: fieldDTO, using: storage)
                field.elective = entity
            }
            entity.customFields = try storage.replace(with: fields)
        }
    }

    func map(_ entity: ElectiveEntity) throws -> Elective {
        Elective(
            id: entity.id,
            name: entity.name,
            startDate: entity.startDate,
            endDate: entity.endDate,
            tracks: try CoreDataStorage.ordered(entity.tracks, as: TrackEntity.self)
                .map(ProgramProjection.track),
            facilitators: try CoreDataStorage.ordered(entity.facilitators, as: FacilitatorEntity.self)
                .map(ProgramProjection.facilitator),
            realLocation: ProgramProjection.location(entity.realLocation),
            customFields: try ProgramProjection.customFields(entity.customFields)
        )
    }
}
