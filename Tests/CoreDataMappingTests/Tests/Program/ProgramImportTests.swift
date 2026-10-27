import CoreData
import Foundation
import Testing
import CoreDataMapping

extension PersistenceTests {
    @MainActor
    @Suite("Program imports")
    struct ProgramImportTests {
        @Test("SQLite repeat, changed membership, shared rows, and parent owned fields")
        func sqliteLifecycle() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("Program.sqlite")
            let stack = try CoreDataStack(storage: .persistent, storeURL: url)
            try await stack.load()

            let tracks = [track(1), track(2)]
            let schedule: ScheduleEventDTO = {
                var dto = scheduleEvent(fields: [field("Schedule")])
                dto.AttendeeStatus = .Accepted
                dto.AcceptStatus = .Unknown
                dto.TeleconferenceType = .Disabled
                dto.Room = .object([
                    "RoomID": .integer(101), "Name": .string("Hall A")
                ])
                return dto
            }()
            let elective: ElectiveDTO = {
                var dto = self.elective(fields: [field("Elective")])
                dto.SeatsLeftCount = 12
                dto.DisableChat = true
                dto.TeleconferenceType = .Disabled
                return dto
            }()
            let appointment = TestDTOFactory.appointment(
                customFields: [field("Appointment")]
            )
            try await stack.importer.transaction { context in
                let storage = CoreDataStorage(context: context)
                try TrackEntityMapper().upsert(tracks, using: storage)
                _ = try AppointmentEntityMapper().upsert([appointment], using: storage)
                try ScheduleEntityMapper().upsert([schedule], using: storage)
                try ElectiveEntityMapper().upsert([elective], using: storage)
            }

            let original = try fetchGraph(stack)
            #expect(original.tracks == [1])
            #expect(original.facilitatorId == 91)
            #expect(original.locationId == "location-2")
            #expect(original.fieldValues == ["Appointment", "Schedule", "Elective"])
            #expect(original.facilitatorCount == 1)
            #expect(original.locationCount == 1)
            #expect(original.trackCount == 2)
            #expect(original.sharedFacilitator)
            #expect(original.sharedLocation)
            #expect(original.ownedDistinct)
            #expect(original.scheduleAttendeeStatus == "Accepted")
            let persistedSchedule = try #require(stack.viewContext.fetch(
                NSFetchRequest<ScheduleEventEntity>(entityName: "ScheduleEventEntity")
            ).first)
            let domainSchedule = try ScheduleEntityMapper().map(persistedSchedule)
            #expect(domainSchedule.eventType == .roomReservation)
            #expect(domainSchedule.reservation == nil)
            #expect(persistedSchedule.acceptStatus == "Unknown")
            #expect(persistedSchedule.teleconferenceType == "Disabled")
            let persistedElective = try #require(stack.viewContext.fetch(
                NSFetchRequest<ElectiveEntity>(entityName: "ElectiveEntity")
            ).first)
            #expect(persistedElective.teleconferenceType == "Disabled")
            let expectedRoomJSON = try ProgramJSONStorage.data(schedule.Room)
            #expect(original.scheduleRoomJSON == expectedRoomJSON)
            #expect(original.electiveSeatsLeftCount == 12)
            #expect(original.electiveDisableChat == true)

            try await stack.importer.transaction { context in
                let storage = CoreDataStorage(context: context)
                try TrackEntityMapper().upsert(tracks, using: storage)
                _ = try AppointmentEntityMapper().upsert([appointment], using: storage)
                try ScheduleEntityMapper().upsert([schedule], using: storage)
                try ElectiveEntityMapper().upsert([elective], using: storage)
            }
            let repeated = try fetchGraph(stack)
            #expect(repeated == original)

            let changed = scheduleEvent(
                trackIds: [2], facilitators: [], includeLocation: false, fields: []
            )
            try await stack.importer.transaction { context in
                try ScheduleEntityMapper().upsert(
                    [changed], using: CoreDataStorage(context: context)
                )
            }
            let updated = try fetchGraph(stack)
            #expect(updated.tracks == [2])
            #expect(updated.facilitatorId == nil)
            #expect(updated.locationId == nil)
            #expect(updated.fieldValues == ["Appointment", "Elective"])
            #expect(updated.scheduleURI == original.scheduleURI)
            #expect(updated.electiveURI == original.electiveURI)
            #expect(updated.facilitatorCount == 1)
            #expect(updated.locationCount == 1)
            #expect(updated.trackCount == 2)
            #expect(updated.ownedDistinct)
            #expect(updated.scheduleAttendeeStatus == nil)
            #expect(updated.scheduleRoomJSON == nil)
            #expect(updated.electiveSeatsLeftCount == 12)

            let reopened = try CoreDataStack(storage: .persistent, storeURL: url)
            try await reopened.load()
            #expect(try fetchGraph(reopened) == updated)
        }

        @Test("A missing Track rolls back only its import batch")
        func missingTrackRollsBackCurrentBatch() async throws {
            let stack = try CoreDataStack(storage: .inMemory)
            try await stack.load()
            let seededTrack = track(1)
            try await stack.importer.transaction { context in
                try TrackEntityMapper().upsert(
                    [seededTrack], using: CoreDataStorage(context: context)
                )
            }
            do {
                try await stack.importer.write(
                    [scheduleEvent(id: 1), scheduleEvent(id: 2, trackIds: [404])],
                    batchSize: 1
                ) { batch, storage in
                    try ScheduleEntityMapper().upsert(batch, using: storage)
                }
                Issue.record("Expected a missing Track error")
            } catch ProgramMappingError.missingTrack(404) {
                // The first batch was committed and the second was rolled back.
            }
            stack.viewContext.reset()
            let events = try stack.viewContext.fetch(
                NSFetchRequest<ScheduleEventEntity>(entityName: "ScheduleEventEntity")
            )
            #expect(events.map(\.id) == [1])
        }

        @Test(
            "Concurrent repositories accept either response completion order",
            arguments: [APIRequest.schedule, .electives]
        )
        func concurrentRequestCompletion(blocked: APIRequest) async throws {
            let stack = try CoreDataStack(storage: .inMemory)
            try await stack.load()
            let gate = ProgramResponseGate(blocked: blocked)
            let client = ProgramClientStub(
                tracks: TracksResponseDTO(ReturnValue: TracksPayloadDTO(Items: [track(1)])),
                schedule: ScheduleResponseDTO(ReturnValue: SchedulePayloadDTO(
                    Events: [ScheduleItemDTO(Event: scheduleEvent(fields: [field("S")]))],
                    Reservations: [ScheduleReservationDTO(
                        RoomReservationUserID: 800, EventID: 101,
                        OwnerUser: TestDTOFactory.defaultUser(id: 9_001),
                        AttendeesCount: 3, UserAttendeeRequired: true,
                        PartnerType: .NotSet
                    )]
                )),
                electives: ElectivesResponseDTO(ReturnValue: ElectivesPayloadDTO(
                    Items: [elective(fields: [field("E")])]
                )),
                gate: gate
            )
            let repository = ProgramRepositoryImpl(apiClient: client, importer: stack.importer)
            let scheduleTask = Task { try await repository.getSchedule() }
            let electiveTask = Task { try await repository.getElectives() }

            await gate.waitUntilBlocked()
            if blocked == .schedule {
                #expect(try await electiveTask.value.count == 1)
            } else {
                #expect(try await scheduleTask.value.count == 1)
            }
            await gate.release()
            #expect(try await scheduleTask.value.count == 1)
            #expect(try await electiveTask.value.count == 1)
            #expect(try await scheduleTask.value.first?.reservation?.id == 800)
            #expect(try await scheduleTask.value.first?.eventType == .roomReservation)
            #expect(try await scheduleTask.value.first?.reservation?.partnerType == .notSet)

            let requests = await gate.requests
            #expect(requests.first == .tracks)
            #expect(requests.filter { $0 == .tracks }.count == 2)
            stack.viewContext.reset()
            #expect(try stack.viewContext.count(
                for: NSFetchRequest<FacilitatorEntity>(entityName: "FacilitatorEntity")
            ) == 1)
            #expect(try stack.viewContext.count(
                for: NSFetchRequest<RealLocationEntity>(entityName: "RealLocationEntity")
            ) == 1)
            #expect(try stack.viewContext.count(
                for: NSFetchRequest<CustomFieldEntity>(entityName: "CustomFieldEntity")
            ) == 2)
            #expect(try stack.viewContext.count(
                for: NSFetchRequest<ScheduleReservationEntity>(
                    entityName: "ScheduleReservationEntity"
                )
            ) == 1)
        }

        private func fetchGraph(_ stack: CoreDataStack) throws -> GraphSnapshot {
            let context = stack.viewContext
            context.reset()
            let schedule = try #require(context.fetch(
                NSFetchRequest<ScheduleEventEntity>(entityName: "ScheduleEventEntity")
            ).first)
            let elective = try #require(context.fetch(
                NSFetchRequest<ElectiveEntity>(entityName: "ElectiveEntity")
            ).first)
            let appointment = try #require(context.fetch(
                NSFetchRequest<AppointmentEntity>(entityName: "AppointmentEntity")
            ).first)
            let appointmentField = try #require(
                (appointment.customFields?.array as? [CustomFieldEntity])?.first
            )
            let electiveField = try #require(
                (elective.customFields?.array as? [CustomFieldEntity])?.first
            )
            let scheduleField = (schedule.customFields?.array as? [CustomFieldEntity])?.first
            let scheduleFacilitator = (schedule.facilitators?.array as? [FacilitatorEntity])?.first
            let electiveFacilitator = (elective.facilitators?.array as? [FacilitatorEntity])?.first
            let count: (String) throws -> Int = { name in
                try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: name))
            }
            return GraphSnapshot(
                scheduleURI: schedule.objectID.uriRepresentation(),
                electiveURI: elective.objectID.uriRepresentation(),
                tracks: (schedule.tracks?.array as? [TrackEntity])?.map(\.id) ?? [],
                facilitatorId: scheduleFacilitator?.id,
                locationId: schedule.realLocation?.id,
                fieldValues: [appointmentField.value, scheduleField?.value, electiveField.value]
                    .compactMap { $0 },
                facilitatorCount: try count("FacilitatorEntity"),
                locationCount: try count("RealLocationEntity"),
                trackCount: try count("TrackEntity"),
                sharedFacilitator: scheduleFacilitator != nil && scheduleFacilitator === electiveFacilitator,
                sharedLocation: schedule.realLocation != nil
                    && schedule.realLocation === elective.realLocation
                    && elective.realLocation === appointment.realLocation,
                ownedDistinct: appointmentField !== electiveField
                    && (scheduleField == nil || (scheduleField !== appointmentField
                        && scheduleField !== electiveField)),
                scheduleAttendeeStatus: schedule.attendeeStatus,
                scheduleRoomJSON: schedule.roomJSON,
                electiveSeatsLeftCount: elective.seatsLeftCount?.intValue,
                electiveDisableChat: elective.disableChat?.boolValue
            )
        }

        private func track(_ id: Int) -> TrackDTO {
            TrackDTO(SeminarTrackID: id, SeminarTrackCategoryID: nil,
                     Name: "Track \(id)", Color: "#123456")
        }

        private func field(_ value: String) -> CustomFieldDTO {
            CustomFieldDTO(CustomFieldID: 7, FieldValue: value, FieldMultipleValues: [])
        }

        private func facilitator() -> FacilitatorDTO {
            FacilitatorDTO(
                FacilitatorID: 91, Ordinal: 1, Prefix: nil, FirstName: "Ada",
                LastName: "Lovelace", FullName: "Ada Lovelace", Title: nil,
                Company: nil, SourceUserID: nil, IconPath: nil, Website: nil,
                FacebookUrl: nil, TwitterUrl: nil, LinkedInUrl: nil, InstagramUrl: nil
            )
        }

        private func location() -> RealLocationDTO {
            RealLocationDTO(RealLocationID: "location-2", Name: "Shared",
                            Address: nil, Lat: 1, Lng: 2)
        }

        private func scheduleEvent(
            id: Int = 1,
            trackIds: [Int] = [1],
            facilitators: [FacilitatorDTO]? = nil,
            includeLocation: Bool = true,
            fields: [CustomFieldDTO] = []
        ) -> ScheduleEventDTO {
            ScheduleEventDTO(
                UniqueID: id, EventID: 100 + id, SeminarVersionID: 3_001,
                EntityEventType: .RoomReservation, Name: "Schedule", Description: nil,
                StartDateTimeUTC: nil, EndDateTimeUTC: nil, Location: nil, Ordinal: 1,
                Tracks: trackIds.map { TrackReferenceDTO(SeminarTrackID: $0) },
                Facilitators: facilitators ?? [facilitator()],
                RealLocation: includeLocation ? location() : nil,
                CustomFieldValues: fields
            )
        }

        private func elective(fields: [CustomFieldDTO]) -> ElectiveDTO {
            ElectiveDTO(
                EventID: 500, Name: "Elective", Description: nil, SubTitle: nil,
                StartDateTimeUTC: nil, EndDateTimeUTC: nil, Location: nil, Ordinal: 1,
                Tracks: [TrackReferenceDTO(SeminarTrackID: 1)],
                Facilitators: [facilitator()], RealLocation: location(),
                CustomFieldValues: fields
            )
        }
    }
}

private nonisolated struct GraphSnapshot: Equatable, Sendable {
    let scheduleURI: URL
    let electiveURI: URL
    let tracks: [Int]
    let facilitatorId: Int?
    let locationId: String?
    let fieldValues: [String]
    let facilitatorCount: Int
    let locationCount: Int
    let trackCount: Int
    let sharedFacilitator: Bool
    let sharedLocation: Bool
    let ownedDistinct: Bool
    let scheduleAttendeeStatus: String?
    let scheduleRoomJSON: Data?
    let electiveSeatsLeftCount: Int?
    let electiveDisableChat: Bool?
}

private actor ProgramResponseGate {
    let blocked: APIRequest
    private(set) var requests: [APIRequest] = []
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var reachedContinuation: CheckedContinuation<Void, Never>?

    init(blocked: APIRequest) { self.blocked = blocked }

    func recordAndWait(_ request: APIRequest) async {
        requests.append(request)
        guard request == blocked else { return }
        await withCheckedContinuation { continuation in
            blockedContinuation = continuation
            reachedContinuation?.resume()
            reachedContinuation = nil
        }
    }

    func waitUntilBlocked() async {
        if blockedContinuation != nil { return }
        await withCheckedContinuation { continuation in
            reachedContinuation = continuation
        }
    }

    func release() {
        blockedContinuation?.resume()
        blockedContinuation = nil
    }
}

private nonisolated struct ProgramClientStub: APIClient {
    let tracks: TracksResponseDTO
    let schedule: ScheduleResponseDTO
    let electives: ElectivesResponseDTO
    let gate: ProgramResponseGate

    func get<Response: Decodable & Sendable>(
        _ responseType: Response.Type, request: APIRequest
    ) async throws -> Response {
        await gate.recordAndWait(request)
        let result: any Sendable
        switch request {
        case .tracks: result = tracks
        case .schedule: result = schedule
        case .electives: result = electives
        case .appointments: throw APIClientStubError.unexpectedRequest(request)
        }
        guard let response = result as? Response else {
            throw APIClientStubError.unexpectedResponseType(String(describing: responseType))
        }
        return response
    }
}
