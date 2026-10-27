import CoreData
import Testing
import CoreDataMapping

extension PersistenceTests {
    @MainActor
    @Suite("Appointment repository")
    struct AppointmentRepositoryTests {

    @Test("Filters API DTOs and persists domain models")
    func filtersAndMapsAppointments() async throws {
        let response = AppointmentsResponseDTO(
            Items: [
                TestDTOFactory.appointment(),
                TestDTOFactory.appointment(
                    id: 200_002,
                    name: "Architecture Review",
                    status: .Planned
                ),
                TestDTOFactory.appointment(
                    id: 200_003,
                    seminarId: 3_002,
                    name: "Different Seminar"
                )
            ]
        )
        let stack = try CoreDataStack(storage: .inMemory)
        try await stack.load()
        let repository = AppointmentRepositoryImpl(
            apiClient: APIClientStub(
                expectedRequest: .appointments(seminarId: 3_001),
                response: response
            ),
            importer: stack.importer
        )

        let appointments = try await repository.getAppointmentsList(for: 3_001)

        #expect(appointments.count == 2)
        #expect(appointments.map(\.id) == [200_001, 200_002])
        #expect(appointments.map(\.name) == ["Customer Discovery", "Architecture Review"])
        #expect(appointments.allSatisfy { !$0.isDraft })
        #expect(appointments.map(\.status) == [.confirmed, .planned])

        stack.viewContext.reset()
        let request = NSFetchRequest<AppointmentEntity>(entityName: "AppointmentEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        let entities = try stack.viewContext.fetch(request)
        #expect(entities.map(\.id) == [200_001, 200_002])
        #expect(entities.allSatisfy { $0.seminarId == 3_001 })
        #expect(entities.map(\.name) == appointments.map(\.name))
    }

    @Test("Generated appointments cross batch boundaries and preserve relationships")
    func importsBundledGraph() async throws {
        let response = AppointmentsResponseDTO(Items: (0..<601).map {
            TestDTOFactory.richAppointment(id: 200_001 + $0)
        })
        #expect(response.Items.count == 601)

        let stack = try CoreDataStack(storage: .inMemory)
        try await stack.load()
        let repository = AppointmentRepositoryImpl(
            apiClient: APIClientStub(
                expectedRequest: .appointments(seminarId: 3_001),
                response: response
            ),
            importer: stack.importer
        )
        let summaries = try await repository.getAppointmentsList(for: 3_001)
        #expect(summaries.count == 601)
        #expect(Set(summaries.map(\.id)).count == 601)
        for index in [0, 399, 400, 499, 500, 600] {
            #expect(summaries[index] == AppointmentSummaryMapper().map(response.Items[index]))
        }

        let dtos = response.Items
        let expectedUserIds = Set(dtos.map { $0.User.UserID }
            + dtos.flatMap { ($0.Attendees ?? []).map(\.UserID) })
        let expectedTopicIds = Set(dtos.flatMap {
            ($0.Topics ?? []).map(\.ReservationTopicID)
        })
        let expectedOpportunityIds = Set(dtos.flatMap {
            ($0.SeminarOpportunities ?? []).map(\.SeminarOpportunityID)
        })
        let expectedLocationIds = Set(dtos.map { $0.RealLocation.RealLocationID })
        let expectedAttendees = dtos.reduce(0) { $0 + ($1.Attendees?.count ?? 0) }
        let expectedFields = dtos.reduce(0) { $0 + ($1.CustomFields?.count ?? 0) }
        let expectedValues = dtos.reduce(0) { total, dto in
            total + (dto.CustomFields ?? []).reduce(0) {
                $0 + $1.FieldMultipleValues.count
            }
        }

        stack.viewContext.reset()
        func rowCount(_ entityName: String) throws -> Int {
            try stack.viewContext.count(
                for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            )
        }
        #expect(try rowCount("AppointmentEntity") == 601)
        #expect(try rowCount("UserEntity") == expectedUserIds.count)
        #expect(try rowCount("AppointmentAttendeeEntity") == expectedAttendees)
        #expect(try rowCount("ReservationTopicEntity") == expectedTopicIds.count)
        #expect(try rowCount("SeminarOpportunityEntity") == expectedOpportunityIds.count)
        #expect(try rowCount("RealLocationEntity") == expectedLocationIds.count)
        #expect(try rowCount("CustomFieldEntity") == expectedFields)
        #expect(try rowCount("CustomFieldValueEntity") == expectedValues)
    }

    @Test("Persists nested models and returns the stored domain model")
    func persistsNestedModelsAndReturnsRoundTrip() async throws {
        let dto = TestDTOFactory.appointment(
            topics: [
                ReservationTopicDTO(ReservationTopicID: 802, Name: "Second"),
                ReservationTopicDTO(ReservationTopicID: 801, Name: "First")
            ],
            customFields: [
                CustomFieldDTO(
                    CustomFieldID: 7,
                    FieldValue: nil,
                    FieldMultipleValues: [
                        CustomFieldValueDTO(
                            FieldValue: "Project Cedar",
                            FieldValueEntityID: 90_020,
                            FieldValueEntityType: .CompanyCustomer
                        )
                    ]
                )
            ]
        )
        let expected = AppointmentSummaryMapper().map(dto)
        let stack = try CoreDataStack(storage: .inMemory)
        try await stack.load()
        let repository = AppointmentRepositoryImpl(
            apiClient: APIClientStub(
                expectedRequest: .appointments(seminarId: 3_001),
                response: AppointmentsResponseDTO(Items: [dto])
            ),
            importer: stack.importer
        )

        let result = try await repository.getAppointmentsList(for: 3_001)

        #expect(result == [expected])
        stack.viewContext.reset()
        let request = NSFetchRequest<AppointmentEntity>(entityName: "AppointmentEntity")
        let entity = try #require(stack.viewContext.fetch(request).first)
        #expect(entity.realLocation?.id == "location-2")
        #expect(
            (entity.topics?.array as? [ReservationTopicEntity])?.map(\.id)
                == [802, 801]
        )
        let fields = entity.customFields?.array as? [CustomFieldEntity]
        #expect(fields?.first?.id == 7)
        #expect(fields?.first?.multipleValues?.count == 1)
    }

    @Test("Returns the final shared graph even when roots repeat across commit boundaries")
    func readsFinalGraphAfterAllBatches() async throws {
        let initial = (1...501).map { id in
            TestDTOFactory.appointment(
                id: id,
                topics: [ReservationTopicDTO(ReservationTopicID: 7, Name: "Initial")]
            )
        }
        let latest = TestDTOFactory.appointment(
            id: 1,
            name: "Final root",
            attendees: [TestDTOFactory.attendee(userId: 10_001)],
            topics: [ReservationTopicDTO(ReservationTopicID: 7, Name: "Final shared topic")]
        )
        let stack = try CoreDataStack(storage: .inMemory)
        try await stack.load()
        let originalAttendeeId = try await stack.importer.transaction { context in
            let entities = try AppointmentEntityMapper().upsert(
                [latest], using: CoreDataStorage(context: context)
            )
            let attendee = try #require(entities.first?.attendees?.first)
            try context.obtainPermanentIDs(for: [attendee])
            return attendee.objectID
        }
        let repository = AppointmentRepositoryImpl(
            apiClient: APIClientStub(
                expectedRequest: .appointments(seminarId: 3_001),
                response: AppointmentsResponseDTO(Items: initial + [latest])
            ),
            importer: stack.importer
        )

        let result = try await repository.getAppointmentsList(for: 3_001)

        #expect(result.map(\.id) == Array(1...501) + [1])
        #expect(result.first == result.last)
        #expect(result.first?.name == "Final root")
        #expect(result.allSatisfy { $0.topics?.first?.name == "Final shared topic" })
        stack.viewContext.reset()
        let roots = NSFetchRequest<AppointmentEntity>(entityName: "AppointmentEntity")
        #expect(try stack.viewContext.count(for: roots) == 501)
        let attendees = NSFetchRequest<AppointmentAttendeeEntity>(entityName: "AppointmentAttendeeEntity")
        #expect(try stack.viewContext.fetch(attendees).map(\.objectID) == [originalAttendeeId])
    }

    @Test("Propagates API-client failures")
    func propagatesAPIClientFailure() async {
        let stack: CoreDataStack
        do {
            stack = try CoreDataStack(storage: .inMemory)
        } catch {
            Issue.record("Could not create Core Data stack: \(error)")
            return
        }
        let repository = AppointmentRepositoryImpl(
            apiClient: APIClientStub(
                expectedRequest: .appointments(seminarId: 3_001),
                error: .expected
            ),
            importer: stack.importer
        )

        do {
            _ = try await repository.getAppointmentsList(for: 3_001)
            Issue.record("Expected the API-client error to be thrown")
        } catch {
            #expect(error as? APIClientStubError == .expected)
        }
    }
    }
}
