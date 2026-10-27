import CoreData
import CoreDataMapping

nonisolated struct ScheduleEntityMapper: Sendable {
    func latestSnapshots(in dtos: [ScheduleEventDTO]) -> [ScheduleEventDTO] {
        ProgramSnapshots.latest(dtos, id: \ScheduleEventDTO.UniqueID)
    }

    func upsert(
        _ dtos: [ScheduleEventDTO],
        reservations: [ScheduleReservationDTO] = [],
        using storage: CoreDataStorage
    ) throws {
        let snapshots = latestSnapshots(in: dtos)
        let eventIds = Set(snapshots.map(\.EventID))
        let relevantReservations = reservations.filter { eventIds.contains($0.EventID) }
        var reservationsByEvent: [Int: ScheduleReservationDTO] = [:]
        for dto in relevantReservations {
            guard reservationsByEvent.updateValue(dto, forKey: dto.EventID) == nil else {
                throw ProgramMappingError.duplicateReservationEvent(dto.EventID)
            }
        }
        let customFields = #keyPath(ScheduleEventEntity.customFields)
        let events = try storage.upsert(
            snapshots,
            id: \ScheduleEventDTO.UniqueID,
            identifiedBy: ScheduleEventEntity.identity,
            prefetching: [customFields, "\(customFields).\(#keyPath(CustomFieldEntity.multipleValues))"]
        ) { entity, dto in
            entity.eventId = dto.EventID
            entity.seminarId = dto.SeminarVersionID
            entity.eventType = dto.EntityEventType.rawValue
            entity.name = dto.Name
            entity.detail = dto.Description
            entity.startDate = dto.StartDateTimeUTC
            entity.endDate = dto.EndDateTimeUTC
            entity.location = dto.Location
            entity.ordinal = dto.Ordinal
            entity.acceptStatus = dto.AcceptStatus?.rawValue
            entity.acceptStatusId = dto.AcceptStatusID.map(NSNumber.init(value:))
            entity.allDayEvent = dto.AllDayEvent.map(NSNumber.init(value:))
            entity.allowVotesForQuestions = dto.AllowVotesForQuestions.map(NSNumber.init(value:))
            entity.analyticDashboardAvailable = dto.AnalyticDashboardAvailable.map(NSNumber.init(value:))
            entity.attendeeStatus = dto.AttendeeStatus?.rawValue
            entity.disableChat = dto.DisableChat.map(NSNumber.init(value:))
            entity.endDateTimeLocal = dto.EndDateTime
            entity.eventIpadDetailImageUrl = dto.EventIpadDetailImageUrl
            entity.eventIphoneMediumImageUrl = dto.EventIphoneMediumImageUrl
            entity.externalEngagementJSON = try ProgramJSONStorage.data(dto.ExternalEngagementID)
            entity.featuredVideoJSON = try ProgramJSONStorage.data(dto.FeaturedVideo)
            entity.hasSponsorRepresentativeRequest = dto.HasSponsorRepresentativeRequest.map(NSNumber.init(value:))
            entity.insightsCount = dto.InsightsCount.map(NSNumber.init(value:))
            entity.isBreakout = dto.IsBreakout.map(NSNumber.init(value:))
            entity.isElective = dto.IsElective.map(NSNumber.init(value:))
            entity.isSplit = dto.IsSplit.map(NSNumber.init(value:))
            entity.isTeleconferencePresentation = dto.IsTeleconferencePresentation.map(NSNumber.init(value:))
            entity.isUserInSeatsList = dto.IsUserInSeatsList.map(NSNumber.init(value:))
            entity.lastModifiedUserId = dto.LastModifiedUserID.map(NSNumber.init(value:))
            entity.locationDataJSON = try ProgramJSONStorage.data(dto.LocationData)
            entity.locationOnIphoneImageUrl = dto.LocationOnIphoneImageUrl
            entity.mapItemJSON = try ProgramJSONStorage.data(dto.MapItem)
            entity.maximumNumberOfRegistrants = dto.MaximumNumberOfRegistrants.map(NSNumber.init(value:))
            entity.originName = dto.OriginName
            entity.postSubTitleJSON = try ProgramJSONStorage.data(dto.PostSubTitle)
            entity.roomJSON = try ProgramJSONStorage.data(dto.Room)
            entity.sectionsJSON = try ProgramJSONStorage.data(dto.Sections)
            entity.showTimeAsAvailable = dto.ShowTimeAsAvailable.map(NSNumber.init(value:))
            entity.speakers = dto.Speakers
            entity.startDateTimeLocal = dto.StartDateTime
            entity.startedSeminarPresentationUniqueIdJSON = try ProgramJSONStorage.data(dto.StartedSeminarPresentationUniqueID)
            entity.subtitle = dto.Subtitle
            entity.supportAskQuestion = dto.SupportAskQuestion.map(NSNumber.init(value:))
            entity.supportWaitingQueue = dto.SupportWaitingQueue.map(NSNumber.init(value:))
            entity.teleconferenceDetails = dto.TeleconferenceDetails
            entity.teleconferenceType = dto.TeleconferenceType?.rawValue
            entity.teleconferenceUrl = dto.TeleconferenceUrl
            entity.teleconferenceUrlTypeJSON = try ProgramJSONStorage.data(dto.TeleconferenceUrlType)
            entity.timeZoneAbbr = dto.TimeZoneAbbr
            entity.timeZoneId = dto.TimeZoneID
            entity.timeZoneOffsetMinutes = dto.TimeZoneOffsetMinutes.map(NSNumber.init(value:))
            entity.visibleForAllUsers = dto.VisibleForAllUsers.map(NSNumber.init(value:))
        }
        let dependencies = try ProgramDependencies(
            trackReferences: snapshots.flatMap { $0.Tracks ?? [] },
            facilitatorDTOs: snapshots.flatMap { $0.Facilitators ?? [] },
            locationDTOs: snapshots.compactMap(\.RealLocation),
            using: storage
        )
        let owners = try storage.upsert(
            relevantReservations.map(\.OwnerUser),
            id: \UserDTO.UserID,
            identifiedBy: UserEntity.identity
        ) { entity, dto in
            entity.prefix = dto.Prefix
            entity.firstName = dto.FirstName
            entity.lastName = dto.LastName
            entity.fullName = dto.FullName
            entity.email = dto.Email
            entity.iconPath = dto.IconPath
            entity.position = dto.Position
            entity.company = dto.Company
        }
        let reservationEntities = try storage.upsert(
            relevantReservations,
            id: \ScheduleReservationDTO.RoomReservationUserID,
            identifiedBy: ScheduleReservationEntity.identity
        ) { entity, dto in
            entity.eventId = dto.EventID
            entity.attendeesCount = dto.AttendeesCount
            entity.userAttendeeRequired = dto.UserAttendeeRequired
            entity.partnerType = dto.PartnerType.rawValue
        }
        let previousReservations = snapshots.compactMap { events[$0.UniqueID]?.reservation }

        for dto in snapshots {
            let entity = events[dto.UniqueID]!
            if let reservationDTO = reservationsByEvent[dto.EventID] {
                let reservation = reservationEntities[reservationDTO.RoomReservationUserID]!
                reservation.ownerUser = owners[reservationDTO.OwnerUser.UserID]!
                entity.reservation = reservation
            } else {
                entity.reservation = nil
            }
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
                field.scheduleEvent = entity
            }
            entity.customFields = try storage.replace(with: fields)
        }
        try storage.deleteSurplusOwned(
            current: previousReservations,
            keeping: Array(reservationEntities.values)
        )
    }

    func map(_ entity: ScheduleEventEntity) throws -> ScheduleEvent {
        ScheduleEvent(
            id: entity.id,
            eventId: entity.eventId,
            seminarId: entity.seminarId,
            eventType: try mapEventType(entity.eventType),
            name: entity.name,
            startDate: entity.startDate,
            endDate: entity.endDate,
            tracks: try CoreDataStorage.ordered(entity.tracks, as: TrackEntity.self)
                .map(ProgramProjection.track),
            facilitators: try CoreDataStorage.ordered(entity.facilitators, as: FacilitatorEntity.self)
                .map(ProgramProjection.facilitator),
            realLocation: ProgramProjection.location(entity.realLocation),
            customFields: try ProgramProjection.customFields(entity.customFields),
            reservation: try entity.reservation.map {
                ScheduleReservation(
                    id: $0.id,
                    ownerUserId: $0.ownerUser?.id,
                    attendeesCount: $0.attendeesCount,
                    userAttendeeRequired: $0.userAttendeeRequired,
                    partnerType: try mapPartnerType($0.partnerType)
                )
            }
        )
    }

    private func mapEventType(_ rawValue: String) throws -> ScheduleEventType {
        guard let type = EventType(rawValue: rawValue) else {
            throw ProgramMappingError.invalidEventType(rawValue)
        }
        return switch type {
        case .Event: .event
        case .RoomReservation: .roomReservation
        }
    }

    private func mapPartnerType(_ rawValue: String) throws -> ScheduleReservationPartnerType {
        guard let type = RoomReservationUserPartnerType(rawValue: rawValue) else {
            throw ProgramMappingError.invalidPartnerType(rawValue)
        }
        return switch type {
        case .NotSet: .notSet
        case .Master: .master
        case .Child: .child
        }
    }
}
