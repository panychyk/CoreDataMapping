import CoreData
import Testing
import CoreDataMapping

extension PersistenceTests {
    @MainActor
    @Suite("Appointment persistence mapper")
    struct AppointmentEntityMapperTests {

        @Test("Upserts a DTO graph and maps the stored entity to domain")
        func upsertsDTOGraph() async throws {
            let stack = try await makeStack()
            let dto = TestDTOFactory.appointment(
                topics: [
                    ReservationTopicDTO(ReservationTopicID: 801, Name: "Product"),
                    ReservationTopicDTO(ReservationTopicID: 802, Name: nil)
                ],
                customFields: [
                    customField(
                        id: 7,
                        value: nil,
                        multipleValue: "Project Cedar"
                    )
                ]
            )
            let mapper = AppointmentEntityMapper()

            let entity = try #require(
                mapper.upsert(
                    [dto],
                    using: CoreDataStorage(context: stack.viewContext)
                ).first
            )

            #expect(entity.id == dto.RoomReservationUserID)
            #expect(entity.seminarId == dto.SeminarID)
            #expect(entity.user?.id == dto.User.UserID)
            #expect(entity.user?.fullName == dto.User.FullName)
            #expect(entity.user?.appointments?.contains(entity) == true)
            #expect(try mapper.map(entity) == AppointmentSummaryMapper().map(dto))
        }

        @Test("Shares the appointment user and replaces only that parent link")
        func sharesAndReplacesAppointmentUser() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()
            let appointments = try mapper.upsert(
                [fullAppointment(id: 1), fullAppointment(id: 2)],
                using: storage
            )
            let sharedUser = try #require(appointments[0].user)
            let firstAttendee = try #require(attendees(of: appointments[0]).first)
            #expect(appointments[1].user === sharedUser)
            #expect(firstAttendee.user === sharedUser)
            #expect(sharedUser.appointments?.count == 2)
            try stack.saveViewContext()

            _ = try mapper.upsert(
                [TestDTOFactory.appointment(
                    id: 1,
                    user: TestDTOFactory.defaultUser(id: 20_001)
                )],
                using: storage
            )
            try stack.saveViewContext()

            #expect(appointments[0].user?.id == 20_001)
            #expect(appointments[1].user === sharedUser)
            #expect(sharedUser.appointments?.count == 1)
            #expect(sharedUser.appointments?.contains(appointments[1]) == true)
            #expect(!sharedUser.isDeleted)
            #expect(fetchCount(UserEntity.self, in: stack.viewContext) == 2)
        }

        @Test("Reimporting a complete graph preserves every persisted identity")
        func reimportsCompleteGraph() async throws {
            let stack = try await makeStack()
            let mapper = AppointmentEntityMapper()
            let dto = fullAppointment()
            let first = try #require(mapper.upsert(
                [dto],
                using: CoreDataStorage(context: stack.viewContext)
            ).first)
            try stack.saveViewContext()
            let originalIds = try graphObjects(of: first).map(\.objectID)
            stack.viewContext.reset()

            let repeated = try #require(mapper.upsert(
                [dto],
                using: CoreDataStorage(context: stack.viewContext)
            ).first)
            try stack.saveViewContext()

            #expect(try graphObjects(of: repeated).map(\.objectID) == originalIds)
            #expect(try mapper.map(repeated) == AppointmentSummaryMapper().map(dto))
            #expect(fetchCount(AppointmentEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(CustomFieldEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(CustomFieldValueEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Nil collections clear full snapshots and delete only owned children")
        func nilCollectionsClearOwnedRelationships() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()
            let appointment = try #require(mapper.upsert(
                [fullAppointment()],
                using: storage
            ).first)
            try stack.saveViewContext()
            let user = appointment.user
            let location = appointment.realLocation
            let empty = TestDTOFactory.appointment(
                id: 1,
                seminarOpportunities: nil,
                attendees: nil,
                topics: nil,
                customFields: nil
            )

            _ = try mapper.upsert([empty], using: storage)
            try stack.saveViewContext()

            #expect(topics(of: appointment).isEmpty)
            #expect(opportunities(of: appointment).isEmpty)
            #expect(attendees(of: appointment).isEmpty)
            #expect(customFields(of: appointment).isEmpty)
            #expect(appointment.user === user)
            #expect(appointment.realLocation === location)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(CustomFieldEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(CustomFieldValueEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(ReservationTopicEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(SeminarOpportunityEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(UserEntity.self, in: stack.viewContext) == 1)
            #expect(try mapper.map(appointment) == AppointmentSummaryMapper().map(empty))
        }

        @Test("Deleting a root cascades through owned children and preserves shared entities")
        func deletingRootPreservesSharedGraph() async throws {
            let stack = try await makeStack()
            let appointments = try AppointmentEntityMapper().upsert(
                [fullAppointment(id: 1), fullAppointment(id: 2)],
                using: CoreDataStorage(context: stack.viewContext)
            )
            try stack.saveViewContext()
            let surviving = appointments[1]
            let survivingIds = try graphObjects(of: surviving).map(\.objectID)

            stack.viewContext.delete(appointments[0])
            try stack.saveViewContext()

            #expect(try graphObjects(of: surviving).map(\.objectID) == survivingIds)
            #expect(surviving.user?.appointments?.count == 1)
            #expect(surviving.realLocation?.appointments?.count == 1)
            #expect(fetchCount(AppointmentEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(CustomFieldEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(CustomFieldValueEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(UserEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(RealLocationEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(ReservationTopicEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(SeminarOpportunityEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Repeated roots apply the last full snapshot once and keep result order")
        func repeatedRootsKeepLastSnapshot() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()
            let existing = try #require(mapper.upsert(
                [fullAppointment()],
                using: storage
            ).first)
            try stack.saveViewContext()
            let existingAttendee = try #require(attendees(of: existing).first)
            let originalIds = try graphObjects(of: existing).map(\.objectID)

            let latest = fullAppointment(
                name: "Latest appointment",
                topicName: "Latest topic",
                attendeeStatus: .Declined
            )
            let results = try mapper.upsert(
                [
                    TestDTOFactory.appointment(id: 1, name: "Discarded snapshot"),
                    fullAppointment(id: 2, topicName: "Middle topic"),
                    latest
                ],
                using: storage
            )
            try stack.saveViewContext()

            #expect(results.map(\.id) == [1, 2, 1])
            #expect(results[0] === results[2])
            #expect(results[0].name == "Latest appointment")
            #expect(topics(of: results[1]).first?.name == "Latest topic")
            #expect(attendees(of: results[0]).first === existingAttendee)
            #expect(existingAttendee.statusRawValue == RoomReservationAttendeeStatus.Declined.rawValue)
            #expect(!existingAttendee.isDeleted)
            #expect(try graphObjects(of: results[0]).map(\.objectID) == originalIds)
            #expect(fetchCount(AppointmentEntity.self, in: stack.viewContext) == 2)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 2)
            #expect(try mapper.map(results[0]) == AppointmentSummaryMapper().map(latest))
        }

        @Test("Discarded root snapshots never preload their obsolete graph")
        func discardedRootSnapshotDoesNotInsertChildren() async throws {
            let stack = try await makeStack()
            let results = try AppointmentEntityMapper().upsert(
                [
                    fullAppointment(),
                    TestDTOFactory.appointment(
                        id: 1,
                        user: TestDTOFactory.defaultUser(id: 20_001)
                    )
                ],
                using: CoreDataStorage(context: stack.viewContext)
            )
            try stack.saveViewContext()

            #expect(results[0] === results[1])
            #expect(results[0].user?.id == 20_001)
            #expect(fetchCount(UserEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(ReservationTopicEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(SeminarOpportunityEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(CustomFieldEntity.self, in: stack.viewContext) == 0)
            #expect(fetchCount(CustomFieldValueEntity.self, in: stack.viewContext) == 0)
        }

        @Test("Reuses an appointment and its to-one location")
        func reusesAppointmentAndLocation() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()
            let first = try #require(
                mapper.upsert(
                    [TestDTOFactory.appointment(name: "Initial")],
                    using: storage
                ).first
            )
            let firstLocation = try #require(first.realLocation)

            let updated = try #require(
                mapper.upsert(
                    [TestDTOFactory.appointment(name: "Updated")],
                    using: storage
                ).first
            )

            #expect(first === updated)
            #expect(updated.name == "Updated")
            #expect(updated.realLocation === firstLocation)
            #expect(fetchCount(AppointmentEntity.self, in: stack.viewContext) == 1)
            #expect(fetchCount(RealLocationEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Shares a real location between appointments by stable ID")
        func sharesRealLocationBetweenAppointments() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let entities = try AppointmentEntityMapper().upsert(
                [
                    TestDTOFactory.appointment(id: 1),
                    TestDTOFactory.appointment(id: 2)
                ],
                using: storage
            )

            let firstLocation = try #require(entities[0].realLocation)
            let secondLocation = try #require(entities[1].realLocation)

            #expect(firstLocation === secondLocation)
            #expect(firstLocation.id == "location-2")
            #expect(firstLocation.appointments?.count == 2)
            #expect(fetchCount(RealLocationEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Shares global topics and replace only changes membership")
        func sharesTopicsAndOnlyReplacesMembership() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()
            let sharedTopic = ReservationTopicDTO(
                ReservationTopicID: 7,
                Name: "Shared"
            )

            let entities = try mapper.upsert(
                [
                    TestDTOFactory.appointment(id: 1, topics: [sharedTopic]),
                    TestDTOFactory.appointment(id: 2, topics: [sharedTopic])
                ],
                using: storage
            )
            let firstTopic = try #require(topics(of: entities[0]).first)
            let secondTopic = try #require(topics(of: entities[1]).first)

            #expect(firstTopic === secondTopic)

            _ = try mapper.upsert(
                [TestDTOFactory.appointment(id: 1, topics: [])],
                using: storage
            )

            #expect(topics(of: entities[0]).isEmpty)
            #expect(topics(of: entities[1]) == [secondTopic])
            #expect(!secondTopic.isDeleted)
            #expect(fetchCount(ReservationTopicEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Scopes equal custom-field IDs to their appointments")
        func scopesCustomFieldsToAppointment() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()

            let entities = try mapper.upsert(
                [
                    TestDTOFactory.appointment(
                        id: 1,
                        customFields: [customField(id: 7, value: "First")]
                    ),
                    TestDTOFactory.appointment(
                        id: 2,
                        customFields: [customField(id: 7, value: "Second")]
                    )
                ],
                using: storage
            )
            let firstField = try #require(customFields(of: entities[0]).first)
            let secondField = try #require(customFields(of: entities[1]).first)

            #expect(firstField !== secondField)
            #expect(firstField.id == secondField.id)
            #expect(firstField.value == "First")
            #expect(secondField.value == "Second")
            try stack.saveViewContext()

            _ = try mapper.upsert(
                [
                    TestDTOFactory.appointment(
                        id: 1,
                        customFields: [customField(id: 7, value: "Updated")]
                    )
                ],
                using: storage
            )

            #expect(customFields(of: entities[0]).first === firstField)
            #expect(firstField.value == "Updated")
            #expect(secondField.value == "Second")

            _ = try mapper.upsert(
                [TestDTOFactory.appointment(id: 1, customFields: [])],
                using: storage
            )

            #expect(customFields(of: entities[0]).isEmpty)
            #expect(customFields(of: entities[1]) == [secondField])
            #expect(firstField.isDeleted)
            #expect(!secondField.isDeleted)
            #expect(
                fetchCount(
                    CustomFieldEntity.self,
                    in: stack.viewContext
                ) == 1
            )
        }

        @Test("Batch upsert does not delete objects omitted by a later payload")
        func doesNotDeleteMissingAppointments() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let mapper = AppointmentEntityMapper()
            let initial = try mapper.upsert(
                [
                    TestDTOFactory.appointment(id: 1),
                    TestDTOFactory.appointment(id: 2)
                ],
                using: storage
            )

            _ = try mapper.upsert(
                [TestDTOFactory.appointment(id: 1, name: "Updated")],
                using: storage
            )

            #expect(initial[0].name == "Updated")
            #expect(!initial[1].isDeleted)
            #expect(fetchCount(AppointmentEntity.self, in: stack.viewContext) == 2)
        }

        @Test("Shares users but owns attendee records per appointment")
        func sharesUsersAndOwnsAttendees() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let sharedUserId = 50_001
            let firstAttendee = attendee(
                userId: sharedUserId,
                status: .Accepted
            )
            let secondAttendee = attendee(
                userId: sharedUserId,
                status: .Declined
            )

            let appointments = try AppointmentEntityMapper().upsert(
                [
                    TestDTOFactory.appointment(id: 1, attendees: [firstAttendee]),
                    TestDTOFactory.appointment(id: 2, attendees: [secondAttendee])
                ],
                using: storage
            )
            let first = try #require(attendees(of: appointments[0]).first)
            let second = try #require(attendees(of: appointments[1]).first)

            #expect(first !== second)
            #expect(first.user === second.user)
            #expect(first.id == "1_50001")
            #expect(second.id == "2_50001")
            #expect(first.statusRawValue == RoomReservationAttendeeStatus.Accepted.rawValue)
            #expect(second.statusRawValue == RoomReservationAttendeeStatus.Declined.rawValue)
            #expect(fetchCount(UserEntity.self, in: stack.viewContext) == 2)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 2)

            _ = try AppointmentEntityMapper().upsert(
                [TestDTOFactory.appointment(id: 1, attendees: [])],
                using: storage
            )

            #expect(first.isDeleted)
            #expect(!second.isDeleted)
            #expect(!second.user!.isDeleted)
            #expect(fetchCount(AppointmentAttendeeEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Shares seminar opportunities and only unlinks surplus")
        func sharesSeminarOpportunities() async throws {
            let stack = try await makeStack()
            let opportunity = SeminarOpportunityDTO(
                SeminarOpportunityID: 70_001,
                Ordinal: 4,
                Name: "Architecture"
            )
            let appointments = try AppointmentEntityMapper().upsert(
                [
                    TestDTOFactory.appointment(
                        id: 1,
                        seminarOpportunities: [opportunity]
                    ),
                    TestDTOFactory.appointment(
                        id: 2,
                        seminarOpportunities: [opportunity]
                    )
                ],
                using: CoreDataStorage(context: stack.viewContext)
            )
            let first = try #require(opportunities(of: appointments[0]).first)
            let second = try #require(opportunities(of: appointments[1]).first)

            #expect(first === second)
            #expect(first.ordinal == 4)

            _ = try AppointmentEntityMapper().upsert(
                [TestDTOFactory.appointment(id: 1, seminarOpportunities: [])],
                using: CoreDataStorage(context: stack.viewContext)
            )

            #expect(opportunities(of: appointments[0]).isEmpty)
            #expect(opportunities(of: appointments[1]) == [second])
            #expect(!second.isDeleted)
        }

        @Test("Uses the last representation of a repeated shared identity")
        func repeatedSharedIdentityUsesLastValue() async throws {
            let stack = try await makeStack()
            let mapper = AppointmentEntityMapper()

            let appointments = try mapper.upsert(
                [
                    TestDTOFactory.appointment(
                        id: 1,
                        topics: [ReservationTopicDTO(
                            ReservationTopicID: 7,
                            Name: "First"
                        )]
                    ),
                    TestDTOFactory.appointment(
                        id: 2,
                        topics: [ReservationTopicDTO(
                            ReservationTopicID: 7,
                            Name: "Latest"
                        )]
                    )
                ],
                using: CoreDataStorage(context: stack.viewContext)
            )
            let first = try #require(topics(of: appointments[0]).first)
            let second = try #require(topics(of: appointments[1]).first)

            #expect(first === second)
            #expect(first.name == "Latest")
            #expect(fetchCount(AppointmentEntity.self, in: stack.viewContext) == 2)
            #expect(fetchCount(ReservationTopicEntity.self, in: stack.viewContext) == 1)
        }

        @Test("Maps missing optional persistence data to domain defaults")
        func mapsMissingPersistenceData() async throws {
            let stack = try await makeStack()
            let entity = try CoreDataStorage(context: stack.viewContext).insert(AppointmentEntity.self)
            entity.name = "Legacy appointment"
            entity.statusRawValue = AppointmentStatus.planned.rawValue

            let appointment = try AppointmentEntityMapper().map(entity)

            #expect(appointment.topics?.isEmpty == true)
            #expect(appointment.realLocation == nil)
            #expect(appointment.customFields?.isEmpty == true)
        }

        @Test("Rejects unknown persisted enum raw values")
        func rejectsUnknownRawValues() async throws {
            let stack = try await makeStack()
            let storage = CoreDataStorage(context: stack.viewContext)
            let appointment = try storage.insert(AppointmentEntity.self)
            appointment.name = "Invalid appointment"
            appointment.statusRawValue = "unknown"

            #expect(throws: AppointmentEntityMappingError.invalidStatus("unknown")) {
                try AppointmentEntityMapper().map(appointment)
            }

            appointment.statusRawValue = AppointmentStatus.confirmed.rawValue
            let field = try storage.insert(CustomFieldEntity.self)
            appointment.customFields = NSOrderedSet(object: field)
            let value = try storage.insert(CustomFieldValueEntity.self)
            value.customField = field
            value.entityTypeRawValue = "unknown"

            #expect(
                throws: CustomFieldEntityMappingError
                    .invalidEntityType("unknown")
            ) {
                try AppointmentEntityMapper().map(appointment)
            }
        }

        private func makeStack() async throws -> CoreDataStack {
            let stack = try CoreDataStack(storage: .inMemory)
            try await stack.load()
            return stack
        }

        private func fullAppointment(
            id: Int = 1,
            name: String = "Complete appointment",
            topicName: String = "Shared topic",
            attendeeStatus: RoomReservationAttendeeStatus = .Accepted
        ) -> AppointmentDTO {
            TestDTOFactory.appointment(
                id: id,
                name: name,
                seminarOpportunities: [SeminarOpportunityDTO(
                    SeminarOpportunityID: 70_001,
                    Ordinal: 4,
                    Name: "Shared opportunity"
                )],
                attendees: [attendee(userId: 10_001, status: attendeeStatus)],
                topics: [ReservationTopicDTO(ReservationTopicID: 7, Name: topicName)],
                customFields: [customField(id: 7, value: "Field", multipleValue: "Value")]
            )
        }

        private func graphObjects(of appointment: AppointmentEntity) throws -> [NSManagedObject] {
            let field = try #require(customFields(of: appointment).first)
            return [
                appointment,
                try #require(appointment.user),
                try #require(appointment.realLocation),
                try #require(topics(of: appointment).first),
                try #require(opportunities(of: appointment).first),
                try #require(attendees(of: appointment).first),
                field,
                try #require(field.multipleValues?.first)
            ]
        }

        private func customField(
            id: Int,
            value: String?,
            multipleValue: String? = nil
        ) -> CustomFieldDTO {
            CustomFieldDTO(
                CustomFieldID: id,
                FieldValue: value,
                FieldMultipleValues: multipleValue.map {
                    [
                        CustomFieldValueDTO(
                            FieldValue: $0,
                            FieldValueEntityID: 90_020,
                            FieldValueEntityType: .CompanyCustomer
                        )
                    ]
                } ?? []
            )
        }

        private func attendee(
            userId: Int,
            status: RoomReservationAttendeeStatus
        ) -> AttendeeDTO {
            AttendeeDTO(
                UserID: userId,
                Status: status,
                StatusUpdatedDateUTC: nil,
                ParticipationStatus: .NotSet,
                StateID: nil,
                CountryID: nil,
                IsCustomer: false,
                Duplicate: false,
                DraftSelectDateEmailOpened: nil,
                InvitationEmailOpened: nil
            )
        }

        private func customFields(
            of entity: AppointmentEntity
        ) -> [CustomFieldEntity] {
            (entity.customFields?.array as? [CustomFieldEntity]) ?? []
        }

        private func topics(
            of entity: AppointmentEntity
        ) -> [ReservationTopicEntity] {
            (entity.topics?.array as? [ReservationTopicEntity]) ?? []
        }

        private func attendees(
            of entity: AppointmentEntity
        ) -> [AppointmentAttendeeEntity] {
            Array(entity.attendees ?? [])
        }

        private func opportunities(
            of entity: AppointmentEntity
        ) -> [SeminarOpportunityEntity] {
            Array(entity.seminarOpportunities ?? [])
        }

        private func fetchCount<Entity: NSManagedObject>(
            _ type: Entity.Type,
            in context: NSManagedObjectContext
        ) -> Int {
            let request = NSFetchRequest<Entity>(
                entityName: String(describing: type)
            )
            return (try? context.count(for: request)) ?? -1
        }
    }
}
