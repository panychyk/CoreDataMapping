import CoreData
import CoreDataMapping

nonisolated enum AppointmentEntityMappingError: Error, Equatable {
    case invalidStatus(String)
}

/// Preloads every stable identity, then maps the DTO graph without fetches.
nonisolated struct AppointmentEntityMapper: Sendable {
    func map(_ entity: AppointmentEntity) throws -> AppointmentSummary {
        guard let status = AppointmentStatus(rawValue: entity.statusRawValue) else {
            throw AppointmentEntityMappingError.invalidStatus(entity.statusRawValue)
        }

        let topics = try CoreDataStorage.ordered(entity.topics, as: ReservationTopicEntity.self)
        let customFields = try CoreDataStorage.ordered(entity.customFields, as: CustomFieldEntity.self)

        return AppointmentSummary(
            id: entity.id,
            startDate: entity.startDate,
            endDate: entity.endDate,
            name: entity.name,
            isDraft: entity.isDraft,
            status: status,
            topics: topics.map { ReservationTopic(id: $0.id, name: $0.name) },
            realLocation: entity.realLocation.map {
                RealLocation(
                    id: $0.id,
                    name: $0.name,
                    address: $0.address,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            },
            customFields: try customFields.map(CustomFieldEntityMapper().map)
        )
    }

    /// Keeps the last full snapshot of each root in last-occurrence order.
    /// Normalize the entire response before batching so an obsolete snapshot
    /// cannot delete owned children or insert unused shared objects in an earlier batch.
    func latestSnapshots(in dtos: [AppointmentDTO]) -> [AppointmentDTO] {
        var seenIds: Set<Int> = []
        return Array(dtos.reversed().filter {
            seenIds.insert($0.RoomReservationUserID).inserted
        }.reversed())
    }

    func upsert(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [AppointmentEntity] {
        let snapshots = latestSnapshots(in: dtos)
        let appointments = try upsertAppointments(snapshots, using: storage)
        let locations = try upsertLocations(snapshots, using: storage)
        let topics = try upsertTopics(snapshots, using: storage)
        let opportunities = try upsertOpportunities(snapshots, using: storage)
        let users = try upsertUsers(snapshots, using: storage)
        let attendees = try preloadAttendees(snapshots, using: storage)

        for dto in snapshots {
            let appointment = appointments[dto.RoomReservationUserID]!
            appointment.user = users[dto.User.UserID]!
            appointment.realLocation = locations[dto.RealLocation.RealLocationID]!
            appointment.topics = try storage.replace(
                with: (dto.Topics ?? []).map {
                    topics[$0.ReservationTopicID]!
                }
            )
            appointment.seminarOpportunities = try storage.replaceUnordered(
                with: (dto.SeminarOpportunities ?? []).map {
                    opportunities[$0.SeminarOpportunityID]!
                }
            )

            try reconcileAttendees(
                dto.Attendees ?? [],
                of: appointment,
                attendees: attendees,
                users: users,
                using: storage
            )
            try reconcileCustomFields(
                dto.CustomFields ?? [],
                of: appointment,
                using: storage
            )
        }

        return dtos.map { appointments[$0.RoomReservationUserID]! }
    }

    private func upsertAppointments(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [Int: AppointmentEntity] {
        let customFields = #keyPath(AppointmentEntity.customFields)
        return try storage.upsert(
            dtos,
            id: \AppointmentDTO.RoomReservationUserID,
            identifiedBy: AppointmentEntity.identity,
            prefetching: [
                #keyPath(AppointmentEntity.attendees),
                customFields,
                "\(customFields).\(#keyPath(CustomFieldEntity.multipleValues))"
            ]
        ) { entity, dto in
            entity.seminarId = dto.SeminarID
            entity.startDate = dto.StartDateUTC
            entity.endDate = dto.EndDateUTC
            entity.name = dto.AppointmentName
            entity.isDraft = dto.IsDraft
            entity.statusRawValue = AppointmentStatusMapper.map(dto.Status).rawValue
        }
    }

    private func upsertLocations(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [String: RealLocationEntity] {
        try storage.upsert(
            dtos.map(\.RealLocation),
            id: \RealLocationDTO.RealLocationID,
            identifiedBy: RealLocationEntity.identity
        ) { entity, dto in
            entity.name = dto.Name
            entity.address = dto.Address
            entity.latitude = dto.Lat
            entity.longitude = dto.Lng
        }
    }

    private func upsertTopics(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [Int: ReservationTopicEntity] {
        try storage.upsert(
            dtos.flatMap { $0.Topics ?? [] },
            id: \ReservationTopicDTO.ReservationTopicID,
            identifiedBy: ReservationTopicEntity.identity
        ) { entity, dto in
            entity.name = dto.Name
        }
    }

    private func upsertOpportunities(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [Int: SeminarOpportunityEntity] {
        try storage.upsert(
            dtos.flatMap { $0.SeminarOpportunities ?? [] },
            id: \SeminarOpportunityDTO.SeminarOpportunityID,
            identifiedBy: SeminarOpportunityEntity.identity
        ) { entity, dto in
            entity.ordinal = dto.Ordinal
            entity.name = dto.Name
        }
    }

    private func upsertUsers(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [Int: UserEntity] {
        let userIds = dtos.flatMap { dto in
            [dto.User.UserID] + (dto.Attendees ?? []).map(\.UserID)
        }
        let users = try storage.upsert(
            ids: userIds,
            identifiedBy: UserEntity.identity
        )

        for dto in dtos.map(\.User) {
            let entity = users[dto.UserID]!
            entity.prefix = dto.Prefix
            entity.firstName = dto.FirstName
            entity.lastName = dto.LastName
            entity.fullName = dto.FullName
            entity.email = dto.Email
            entity.iconPath = dto.IconPath
            entity.position = dto.Position
            entity.company = dto.Company
        }

        return users
    }

    private func preloadAttendees(
        _ dtos: [AppointmentDTO],
        using storage: CoreDataStorage
    ) throws -> [String: AppointmentAttendeeEntity] {
        let attendeeIds = dtos.flatMap { dto in
            (dto.Attendees ?? []).map {
                AppointmentAttendeeEntity.makeId(
                    appointmentId: dto.RoomReservationUserID,
                    userId: $0.UserID
                )
            }
        }
        return try storage.upsert(
            ids: attendeeIds,
            identifiedBy: AppointmentAttendeeEntity.identity
        )
    }

    private func reconcileAttendees(
        _ dtos: [AttendeeDTO],
        of appointment: AppointmentEntity,
        attendees: [String: AppointmentAttendeeEntity],
        users: [Int: UserEntity],
        using storage: CoreDataStorage
    ) throws {
        let current = appointment.attendees ?? []
        let incoming = dtos.map { dto in
            let id = AppointmentAttendeeEntity.makeId(
                appointmentId: appointment.id,
                userId: dto.UserID
            )
            let entity = attendees[id]!
            entity.statusRawValue = dto.Status.rawValue
            entity.statusUpdatedDateUTC = dto.StatusUpdatedDateUTC
            entity.participationStatusRawValue = dto.ParticipationStatus.rawValue
            entity.stateId = dto.StateID.map(NSNumber.init(value:))
            entity.countryId = dto.CountryID.map(NSNumber.init(value:))
            entity.isCustomer = dto.IsCustomer
            entity.duplicate = dto.Duplicate
            entity.draftSelectDateEmailOpened = dto.DraftSelectDateEmailOpened
            entity.invitationEmailOpened = dto.InvitationEmailOpened
            entity.appointment = appointment
            entity.user = users[dto.UserID]!
            return entity
        }

        appointment.attendees = try storage.replaceUnordered(with: incoming)
        try storage.deleteSurplusOwned(current: current, keeping: incoming)
    }

    private func reconcileCustomFields(
        _ dtos: [CustomFieldDTO],
        of appointment: AppointmentEntity,
        using storage: CoreDataStorage
    ) throws {
        let current = try CoreDataStorage.ordered(appointment.customFields, as: CustomFieldEntity.self)
        let mapper = CustomFieldEntityMapper()
        let incoming = try storage.reconcileOwned(
            dtos,
            current: current,
            dtoId: \CustomFieldDTO.CustomFieldID,
            entityId: \CustomFieldEntity.id,
            create: { try storage.insert(CustomFieldEntity.self) }
        ) { entity, dto in
            try mapper.update(entity, from: dto, using: storage)
            entity.appointment = appointment
        }

        appointment.customFields = try storage.replace(with: incoming)
    }
}
