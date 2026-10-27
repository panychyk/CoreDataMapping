import CoreData
import Foundation
import Testing
import CoreDataMapping

// MARK: - Configuration

/// Shape of one seminar response. Every count is a per-appointment fan-out
/// unless the name says pool: pools are shared rows that later requests re-fetch
/// instead of inserting.
nonisolated struct PerfGraphShape: Sendable {
    var seminars = 4
    var appointmentsPerSeminar = 4_000
    var attendeesPerAppointment = 4
    var topicsPerAppointment = 3
    var opportunitiesPerAppointment = 2
    var customFieldsPerAppointment = 3
    var valuesPerCustomField = 2
    /// Shared across all seminars: cross-request contention on the same rows.
    var topicPool = 40
    var locationPool = 8
    /// Attendee identities recur inside and across seminars, like a real HCP list.
    var attendeeUserPool = 8_000
    var organizerPoolPerSeminar = 50

    var rootsPerSeminar: Int { appointmentsPerSeminar }
    var attendeeRowsPerSeminar: Int { appointmentsPerSeminar * attendeesPerAppointment }
    var customFieldRowsPerSeminar: Int { appointmentsPerSeminar * customFieldsPerAppointment }
    var customValueRowsPerSeminar: Int { customFieldRowsPerSeminar * valuesPerCustomField }

    /// Rows written for one seminar, excluding pooled shared rows.
    var ownedRowsPerSeminar: Int {
        rootsPerSeminar + attendeeRowsPerSeminar
            + customFieldRowsPerSeminar + customValueRowsPerSeminar
    }

    var describedFanout: String {
        """
        \(seminars) seminars x \(appointmentsPerSeminar) appointments; \
        per appointment: \(attendeesPerAppointment) attendees, \(topicsPerAppointment) topics, \
        \(opportunitiesPerAppointment) opportunities, \(customFieldsPerAppointment) custom fields \
        x \(valuesPerCustomField) values
        """
    }
}

// MARK: - Fixture

nonisolated struct SeminarPayload: Sendable {
    let seminarId: Int
    let dtos: [AppointmentDTO]
}

/// Builds payloads by index arithmetic only: no RNG and no Date, so two runs
/// compare like for like and a resumed measurement produces the same graph.
nonisolated struct PerfFixture: Sendable {
    let shape: PerfGraphShape

    func payloads() -> [SeminarPayload] {
        (0..<shape.seminars).map(payload(seminarIndex:))
    }

    func rootId(seminarIndex: Int, index: Int) -> Int {
        1_000_000 * (seminarIndex + 1) + index
    }

    func payload(seminarIndex: Int) -> SeminarPayload {
        let seminarId = 3_000 + seminarIndex
        let dtos = (0..<shape.appointmentsPerSeminar).map {
            appointment(seminarIndex: seminarIndex, seminarId: seminarId, index: $0)
        }
        return SeminarPayload(seminarId: seminarId, dtos: dtos)
    }

    /// `revision` models a server-side edit of the same root: scalars change,
    /// one attendee is swapped for another and every custom value is rewritten.
    private func appointment(
        seminarIndex: Int,
        seminarId: Int,
        index: Int,
        revision: Int = 0
    ) -> AppointmentDTO {
        let appointmentId = rootId(seminarIndex: seminarIndex, index: index)
        let organizerId = 10_000_000 + seminarIndex * 100_000
            + index % max(shape.organizerPoolPerSeminar, 1)

        return TestDTOFactory.appointment(
            id: appointmentId,
            seminarId: seminarId,
            name: "Appointment \(appointmentId) r\(revision)",
            startDate: TestDTOFactory.defaultStartDate.addingTimeInterval(Double(index) * 900),
            endDate: TestDTOFactory.defaultEndDate.addingTimeInterval(Double(index) * 900),
            status: (index + revision).isMultiple(of: 3) ? .Confirmed : .Planned,
            seminarOpportunities: opportunities(seminarIndex: seminarIndex, index: index),
            attendees: attendees(index: index, seminarIndex: seminarIndex, revision: revision),
            topics: topics(index: index),
            realLocation: location(index: index),
            user: TestDTOFactory.defaultUser(id: organizerId),
            customFields: customFields(appointmentId: appointmentId, revision: revision)
        )
    }

    private func topics(index: Int) -> [ReservationTopicDTO] {
        (0..<shape.topicsPerAppointment).map { offset in
            let id = (index * shape.topicsPerAppointment + offset) % max(shape.topicPool, 1) + 1
            return ReservationTopicDTO(ReservationTopicID: id, Name: "Topic \(id)")
        }
    }

    private func opportunities(seminarIndex: Int, index: Int) -> [SeminarOpportunityDTO] {
        (0..<shape.opportunitiesPerAppointment).map { offset in
            let id = 1_000 * (seminarIndex + 1) + (index + offset) % 20
            return SeminarOpportunityDTO(
                SeminarOpportunityID: id, Ordinal: offset + 1, Name: "Opportunity \(id)"
            )
        }
    }

    private func location(index: Int) -> RealLocationDTO {
        let id = index % max(shape.locationPool, 1)
        return RealLocationDTO(
            RealLocationID: "location-\(id)",
            Name: "Venue \(id)",
            Address: "Street \(id)",
            Lat: 43.5 + Double(id) / 100,
            Lng: 16.4 + Double(id) / 100
        )
    }

    private func attendees(
        index: Int,
        seminarIndex: Int,
        revision: Int = 0
    ) -> [AttendeeDTO] {
        let stride = shape.attendeesPerAppointment
        return (0..<stride).map { offset in
            // A revision replaces the last attendee only: one owned row is deleted
            // and one inserted, which is the expensive half of a warm update.
            let swap = revision > 0 && offset == stride - 1 ? revision * 7_919 : 0
            let slot = (index * stride + offset + seminarIndex * 977 + swap)
                % max(shape.attendeeUserPool, 1)
            return TestDTOFactory.attendee(userId: 20_000_000 + slot)
        }
    }

    private func customFields(appointmentId: Int, revision: Int = 0) -> [CustomFieldDTO] {
        (1...max(shape.customFieldsPerAppointment, 1)).map { fieldId in
            CustomFieldDTO(
                CustomFieldID: fieldId,
                FieldValue: "Field \(fieldId)",
                FieldMultipleValues: (1...max(shape.valuesPerCustomField, 1)).map { valueIndex in
                    CustomFieldValueDTO(
                        FieldValue: "Value \(appointmentId)-\(fieldId)-\(valueIndex) r\(revision)",
                        FieldValueEntityID: appointmentId * 100 + fieldId * 10 + valueIndex,
                        FieldValueEntityType: .CompanyCustomer
                    )
                }
            )
        }
    }
}

/// One server change against an already seeded seminar.
nonisolated struct PerfDelta: Sendable {
    let seminarId: Int
    let changedIds: [Int]
    let addedIds: [Int]
    let removedIds: [Int]
    /// Only the touched roots, as a delta endpoint would send them.
    let upserted: [AppointmentDTO]
    /// The whole seminar after the change, as `getAppointmentsList` sends it today.
    let fullList: [AppointmentDTO]
}

extension PerfFixture {
    /// Derives a small change for one seeded seminar: `size` roots edited, `size`
    /// new roots and `size` roots dropped from the response. Edited and dropped
    /// roots are taken from opposite ends so they never overlap.
    func delta(seminarIndex: Int, size: Int) -> PerfDelta {
        let count = shape.appointmentsPerSeminar
        let size = max(min(size, count / 2), 0)
        let seminarId = 3_000 + seminarIndex
        let changedIndexes = Set(0..<size)
        let removedIndexes = Set((count - size)..<count)

        func dto(_ index: Int, revision: Int = 0) -> AppointmentDTO {
            appointment(
                seminarIndex: seminarIndex,
                seminarId: seminarId,
                index: index,
                revision: revision
            )
        }

        let changed = (0..<size).map { dto($0, revision: 1) }
        let added = (count..<(count + size)).map { dto($0) }

        return PerfDelta(
            seminarId: seminarId,
            changedIds: changed.map(\.RoomReservationUserID),
            addedIds: added.map(\.RoomReservationUserID),
            removedIds: removedIndexes.sorted().map {
                rootId(seminarIndex: seminarIndex, index: $0)
            },
            upserted: changed + added,
            fullList: fullList(seminarIndex: seminarIndex, size: size) {
                changedIndexes.contains($0) ? 1 : 0
            }
        )
    }

    /// The seminar as the current endpoint returns it after the change: every
    /// surviving root plus the added ones, each at the revision `revision` picks.
    /// Pass a constant to model a response in which everything changed at once.
    func fullList(
        seminarIndex: Int,
        size: Int,
        revision: (Int) -> Int
    ) -> [AppointmentDTO] {
        let count = shape.appointmentsPerSeminar
        let size = max(min(size, count / 2), 0)
        let survivors = (0..<(count - size)).map { $0 } + (count..<(count + size))
        return survivors.map {
            appointment(
                seminarIndex: seminarIndex,
                seminarId: 3_000 + seminarIndex,
                index: $0,
                revision: revision($0)
            )
        }
    }
}

// MARK: - Reporting

nonisolated struct PerfSample: Sendable {
    let label: String
    let roots: Int
    let seconds: Double
}

nonisolated enum PerfReport {
    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) * 1e-18
    }

    static func print(
        _ title: String,
        shape: PerfGraphShape? = nil,
        showRate: Bool = true,
        samples: [PerfSample]
    ) {
        var lines = ["PERF | === \(title) ==="]
        if let shape { lines.append("PERF | \(shape.describedFanout)") }
        for sample in samples {
            let rate = showRate
                ? (sample.roots > 0 && sample.seconds > 0
                    ? String(format: "%.0f roots/s", Double(sample.roots) / sample.seconds)
                    : "-")
                : ""
            lines.append(
                String(
                    format: "PERF | %-38@ %8.2fs  %@",
                    sample.label as NSString,
                    sample.seconds,
                    rate as NSString
                )
            )
        }
        Swift.print(lines.joined(separator: "\n"))
    }
}

nonisolated enum MixedImportMode: String, CaseIterable, Sendable {
    case sequentialShared
    case concurrentShared
}

nonisolated enum MixedRequest: String, CaseIterable, Sendable {
    case tracks
    case schedule
    case electives
    case appointments

    func execute(client: DefaultAPIClient, importer: CoreDataImporter) async throws -> Int {
        let program = ProgramRepositoryImpl(apiClient: client, importer: importer)
        switch self {
        case .tracks:
            return try await program.getTracks().count
        case .schedule:
            return try await program.getSchedule().count
        case .electives:
            return try await program.getElectives().count
        case .appointments:
            return try await AppointmentRepositoryImpl(
                apiClient: client, importer: importer
            ).getAppointmentsList(for: 3_001).count
        }
    }

    var expectedCount: Int {
        switch self {
        case .tracks: 39
        case .schedule: 2_250
        case .electives: 15_178
        case .appointments: 4_000
        }
    }

    var entityName: String {
        switch self {
        case .tracks: "TrackEntity"
        case .schedule: "ScheduleEventEntity"
        case .electives: "ElectiveEntity"
        case .appointments: "AppointmentEntity"
        }
    }
}

// MARK: - Tests

extension PersistenceTests {
    @MainActor
    @Suite("Import performance", .serialized)
    struct CoreDataImportPerformanceTests {

        /// All four bundled endpoints share one SQLite store. The same store is
        /// refreshed after the cold run so each mode also measures warm mapping.
        @Test("Mixed bundled requests: sequential and concurrent cold/warm imports",
              arguments: MixedImportMode.allCases)
        func mixedBundledRequests(mode: MixedImportMode) async throws {
            try await withSQLiteStack { stack in
                let client = DefaultAPIClient.local()
                for phase in ["cold", "warm"] {
                    let samples = try await runMixedRequests(
                        mode: mode, phase: phase, client: client, stack: stack
                    )
                    PerfReport.print(
                        "mixed bundled \(mode.rawValue), \(phase)",
                        showRate: false,
                        samples: samples
                    )
                    try await expectMixedCounts(in: stack)
                }
            }
        }

        /// The bundled 4,000-root payload isolates JSON decoding, Core Data
        /// writes, and the actual API-to-domain path on fresh SQLite stores.
        @Test("Bundled appointments: decode, write, repeat, and full cycle")
        func bundledAppointmentPhases() async throws {
            let url = try #require(Bundle.module.url(
                forResource: "appointments", withExtension: "json"
            ))
            let data = try Data(contentsOf: url)
            let decodeStart = ContinuousClock.now
            let response = try APIJSONDecoder.make().decode(
                AppointmentsResponseDTO.self, from: data
            )
            let decodeSeconds = PerfReport.seconds(decodeStart.duration(to: .now))
            #expect(response.Items.count == 4_000)

            let mapper = AppointmentEntityMapper()
            let snapshots = mapper.latestSnapshots(in: response.Items)
            var writeSeconds = 0.0
            var repeatSeconds = 0.0
            try await withSQLiteStack { stack in
                let start = ContinuousClock.now
                try await stack.importer.write(snapshots) { batch, storage in
                    _ = try mapper.upsert(batch, using: storage)
                }
                writeSeconds = PerfReport.seconds(start.duration(to: .now))
                let repeatStart = ContinuousClock.now
                try await stack.importer.write(snapshots) { batch, storage in
                    _ = try mapper.upsert(batch, using: storage)
                }
                repeatSeconds = PerfReport.seconds(repeatStart.duration(to: .now))
            }

            var fullCycleSeconds = 0.0
            try await withSQLiteStack { stack in
                let repository = AppointmentRepositoryImpl(
                    apiClient: DefaultAPIClient { _ in data }, importer: stack.importer
                )
                let start = ContinuousClock.now
                let summaries = try await repository.getAppointmentsList(for: 3_001)
                fullCycleSeconds = PerfReport.seconds(start.duration(to: .now))
                #expect(summaries.count == 4_000)
            }
            Swift.print(String(
                format: "PERF | bundled 4000 | decode %.3fs | SQLite write %.3fs | repeat %.3fs | API→DTO→write→read %.3fs",
                decodeSeconds, writeSeconds, repeatSeconds, fullCycleSeconds
            ))
        }

        @Test("Bundled program: decode, write, and full cycles")
        func bundledProgramPhases() async throws {
            func fixture(_ name: String) throws -> Data {
                let url = try #require(Bundle.module.url(
                    forResource: name, withExtension: "json"
                ))
                return try Data(contentsOf: url)
            }
            let trackData = try fixture("tracks")
            let scheduleData = try fixture("schedule")
            let electiveData = try fixture("electives")
            let decoder = APIJSONDecoder.make()

            let trackDecodeStart = ContinuousClock.now
            let tracks = try decoder.decode(TracksResponseDTO.self, from: trackData)
            let trackDecode = PerfReport.seconds(trackDecodeStart.duration(to: .now))
            let scheduleDecodeStart = ContinuousClock.now
            let schedule = try decoder.decode(ScheduleResponseDTO.self, from: scheduleData)
            let scheduleDecode = PerfReport.seconds(scheduleDecodeStart.duration(to: .now))
            let electiveDecodeStart = ContinuousClock.now
            let electives = try decoder.decode(ElectivesResponseDTO.self, from: electiveData)
            let electiveDecode = PerfReport.seconds(electiveDecodeStart.duration(to: .now))

            let scheduleEvents = schedule.ReturnValue.Events.map(\.Event)
            let reservationsByEvent = Dictionary(
                grouping: schedule.ReturnValue.Reservations, by: \.EventID
            )
            var trackWrite = 0.0
            var scheduleWrite = 0.0
            var electiveWrite = 0.0
            try await withSQLiteStack { stack in
                let importer = stack.importer
                let trackMapper = TrackEntityMapper()
                let scheduleMapper = ScheduleEntityMapper()
                let electiveMapper = ElectiveEntityMapper()
                let trackStart = ContinuousClock.now
                try await importer.write(tracks.ReturnValue.Items) { batch, storage in
                    try trackMapper.upsert(batch, using: storage)
                }
                trackWrite = PerfReport.seconds(trackStart.duration(to: .now))
                let scheduleStart = ContinuousClock.now
                try await importer.write(scheduleEvents) { batch, storage in
                    try scheduleMapper.upsert(
                        batch,
                        reservations: batch.flatMap { reservationsByEvent[$0.EventID] ?? [] },
                        using: storage
                    )
                }
                scheduleWrite = PerfReport.seconds(scheduleStart.duration(to: .now))
                let electiveStart = ContinuousClock.now
                try await importer.write(electives.ReturnValue.Items) { batch, storage in
                    try electiveMapper.upsert(batch, using: storage)
                }
                electiveWrite = PerfReport.seconds(electiveStart.duration(to: .now))
            }

            var scheduleCycle = 0.0
            try await withSQLiteStack { stack in
                let repository = ProgramRepositoryImpl(
                    apiClient: DefaultAPIClient.local(), importer: stack.importer
                )
                let start = ContinuousClock.now
                let events = try await repository.getSchedule()
                #expect(events.count == 2_250)
                scheduleCycle = PerfReport.seconds(start.duration(to: .now))
            }
            var electiveCycle = 0.0
            try await withSQLiteStack { stack in
                let repository = ProgramRepositoryImpl(
                    apiClient: DefaultAPIClient.local(), importer: stack.importer
                )
                let start = ContinuousClock.now
                let items = try await repository.getElectives()
                #expect(items.count == 15_178)
                electiveCycle = PerfReport.seconds(start.duration(to: .now))
            }
            Swift.print(String(
                format: "PERF | tracks %d | decode %.3fs | SQLite write %.3fs",
                tracks.ReturnValue.Items.count, trackDecode, trackWrite
            ))
            Swift.print(String(
                format: "PERF | schedule %d events + %d reservations | decode %.3fs | SQLite write %.3fs | full cycle %.3fs",
                scheduleEvents.count, schedule.ReturnValue.Reservations.count,
                scheduleDecode, scheduleWrite, scheduleCycle
            ))
            Swift.print(String(
                format: "PERF | electives %d | decode %.3fs | SQLite write %.3fs | full cycle %.3fs",
                electives.ReturnValue.Items.count, electiveDecode, electiveWrite, electiveCycle
            ))
        }

        /// Baseline service time: nothing is queued behind anything else, so each
        /// number is the cost of one seminar on an otherwise idle context.
        @Test("Four seminars imported one after another on the shared context")
        func sequentialImportsOnOneContext() async throws {
            let shape = PerfGraphShape()
            let payloads = PerfFixture(shape: shape).payloads()

            try await withSQLiteStack { stack in
                var samples: [PerfSample] = []
                let coldStart = ContinuousClock.now
                for payload in payloads {
                    let start = ContinuousClock.now
                    try await write(payload, using: stack.importer)
                    samples.append(
                        PerfSample(
                            label: "insert seminar \(payload.seminarId)",
                            roots: payload.dtos.count,
                            seconds: PerfReport.seconds(start.duration(to: .now))
                        )
                    )
                }
                let coldTotal = coldStart.duration(to: .now)

                // Second pass hits the update path: every root, attendee and owned
                // child already exists, so this is what a refresh actually costs.
                let warmStart = ContinuousClock.now
                for payload in payloads {
                    let start = ContinuousClock.now
                    try await write(payload, using: stack.importer)
                    samples.append(
                        PerfSample(
                            label: "update seminar \(payload.seminarId)",
                            roots: payload.dtos.count,
                            seconds: PerfReport.seconds(start.duration(to: .now))
                        )
                    )
                }
                let warmTotal = warmStart.duration(to: .now)

                let roots = shape.seminars * shape.appointmentsPerSeminar
                samples.append(
                    PerfSample(
                        label: "TOTAL all inserts",
                        roots: roots,
                        seconds: PerfReport.seconds(coldTotal)
                    )
                )
                samples.append(
                    PerfSample(
                        label: "TOTAL all updates",
                        roots: roots,
                        seconds: PerfReport.seconds(warmTotal)
                    )
                )
                PerfReport.print(
                    "sequential, one context, batch \(CoreDataImporter.defaultBatchSize)",
                    shape: shape,
                    samples: samples
                )

                try await expectRowCounts(shape, in: stack)
            }
        }

        /// Four responses arrive at once and use the same importer context.
        /// Each `write` occupies one enqueued block, so calls do not interleave.
        /// Each batch commits separately; rollback covers only the current batch.
        @Test("Four concurrent seminar imports queue behind one context")
        func concurrentImportsOnOneContext() async throws {
            let shape = PerfGraphShape()
            let payloads = PerfFixture(shape: shape).payloads()

            try await withSQLiteStack { stack in
                let importer = stack.importer
                let start = ContinuousClock.now
                let latencies = try await withThrowingTaskGroup(
                    of: (Int, Double).self
                ) { group in
                    for payload in payloads {
                        group.addTask {
                            let taskStart = ContinuousClock.now
                            try await write(payload, using: importer)
                            return (
                                payload.seminarId,
                                PerfReport.seconds(taskStart.duration(to: .now))
                            )
                        }
                    }
                    var results: [(Int, Double)] = []
                    for try await result in group { results.append(result) }
                    return results
                }
                let total = PerfReport.seconds(start.duration(to: .now))

                var samples = latencies
                    .sorted { $0.1 < $1.1 }
                    .map {
                        PerfSample(
                            label: "latency seminar \($0.0)",
                            roots: shape.appointmentsPerSeminar,
                            seconds: $0.1
                        )
                    }
                samples.append(
                    PerfSample(
                        label: "TOTAL wall clock",
                        roots: shape.seminars * shape.appointmentsPerSeminar,
                        seconds: total
                    )
                )
                PerfReport.print(
                    "concurrent, one context, batch \(CoreDataImporter.defaultBatchSize)",
                    shape: shape,
                    samples: samples
                )

                // Queueing must not lose or duplicate anything.
                try await expectRowCounts(shape, in: stack)
            }
        }

        /// Counterfactual for the same payloads: one private context per request.
        /// Mapping and fetching overlap, saves still contend on the coordinator,
        /// and shared rows now resolve through the merge policy instead of by
        /// being written once.
        @Test("Four concurrent seminar imports on four private contexts")
        func concurrentImportsOnSeparateContexts() async throws {
            let shape = PerfGraphShape()
            let payloads = PerfFixture(shape: shape).payloads()

            try await withSQLiteStack { stack in
                let container = stack.persistentContainer
                let importers = payloads.map { _ in
                    CoreDataImporter(context: container.newBackgroundContext())
                }
                let start = ContinuousClock.now
                let latencies = try await withThrowingTaskGroup(
                    of: (Int, Double).self
                ) { group in
                    for (payload, importer) in zip(payloads, importers) {
                        group.addTask {
                            let taskStart = ContinuousClock.now
                            try await write(payload, using: importer)
                            return (
                                payload.seminarId,
                                PerfReport.seconds(taskStart.duration(to: .now))
                            )
                        }
                    }
                    var results: [(Int, Double)] = []
                    for try await result in group { results.append(result) }
                    return results
                }
                let total = PerfReport.seconds(start.duration(to: .now))

                var samples = latencies
                    .sorted { $0.1 < $1.1 }
                    .map {
                        PerfSample(
                            label: "latency seminar \($0.0)",
                            roots: shape.appointmentsPerSeminar,
                            seconds: $0.1
                        )
                    }
                samples.append(
                    PerfSample(
                        label: "TOTAL wall clock",
                        roots: shape.seminars * shape.appointmentsPerSeminar,
                        seconds: total
                    )
                )
                PerfReport.print(
                    "concurrent, four contexts, batch \(CoreDataImporter.defaultBatchSize)",
                    shape: shape,
                    samples: samples
                )

                try await expectRowCounts(shape, in: stack)
            }
        }

        /// End-to-end cost the caller actually waits for: normalize, write, then
        /// read every requested id back as a domain summary.
        @Test("Four concurrent repository calls, write plus read")
        func repositoryEndToEnd() async throws {
            let shape = PerfGraphShape()
            let payloads = PerfFixture(shape: shape).payloads()

            try await withSQLiteStack { stack in
                let repositories = payloads.map { payload in
                    AppointmentRepositoryImpl(
                        apiClient: APIClientStub(
                            expectedRequest: .appointments(seminarId: payload.seminarId),
                            response: AppointmentsResponseDTO(Items: payload.dtos)
                        ),
                        importer: stack.importer
                    )
                }

                let start = ContinuousClock.now
                let latencies = try await withThrowingTaskGroup(
                    of: (Int, Int, Double).self
                ) { group in
                    for (payload, repository) in zip(payloads, repositories) {
                        let seminarId = payload.seminarId
                        group.addTask {
                            let taskStart = ContinuousClock.now
                            let summaries = try await repository
                                .getAppointmentsList(for: seminarId)
                            return (
                                seminarId,
                                summaries.count,
                                PerfReport.seconds(taskStart.duration(to: .now))
                            )
                        }
                    }
                    var results: [(Int, Int, Double)] = []
                    for try await result in group { results.append(result) }
                    return results
                }
                let total = PerfReport.seconds(start.duration(to: .now))

                for (_, count, _) in latencies {
                    #expect(count == shape.appointmentsPerSeminar)
                }

                var samples = latencies
                    .sorted { $0.2 < $1.2 }
                    .map {
                        PerfSample(
                            label: "write+read seminar \($0.0)",
                            roots: shape.appointmentsPerSeminar,
                            seconds: $0.2
                        )
                    }
                samples.append(
                    PerfSample(
                        label: "TOTAL wall clock",
                        roots: shape.seminars * shape.appointmentsPerSeminar,
                        seconds: total
                    )
                )
                PerfReport.print(
                    "repository end to end, one context",
                    shape: shape,
                    samples: samples
                )

                try await expectRowCounts(shape, in: stack)
            }
        }

        /// Isolates the read half measured above, so a slow end-to-end number can
        /// be attributed to persistence or to domain projection.
        @Test("Read back one seminar as domain summaries")
        func readBackOneSeminar() async throws {
            var shape = PerfGraphShape()
            shape.seminars = 1
            let payload = PerfFixture(shape: shape).payload(seminarIndex: 0)

            try await withSQLiteStack { stack in
                let writeStart = ContinuousClock.now
                try await write(payload, using: stack.importer)
                let writeSeconds = PerfReport.seconds(writeStart.duration(to: .now))

                let ids = payload.dtos.map(\.RoomReservationUserID)
                let readStart = ContinuousClock.now
                let summaries = try await stack.importer.read(ids) { ids, storage in
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
                    let mapper = AppointmentEntityMapper()
                    return try ids.compactMap { try entities[$0].map(mapper.map) }
                }
                let readSeconds = PerfReport.seconds(readStart.duration(to: .now))

                #expect(summaries.count == payload.dtos.count)
                PerfReport.print(
                    "single seminar write vs read",
                    shape: shape,
                    samples: [
                        PerfSample(
                            label: "write", roots: payload.dtos.count, seconds: writeSeconds
                        ),
                        PerfSample(
                            label: "read + domain mapping",
                            roots: payload.dtos.count,
                            seconds: readSeconds
                        )
                    ]
                )
            }
        }

        /// Warm path. The store already holds every seminar, then each seminar
        /// reports a handful of edits, additions and removals. Two shapes of the
        /// same change are timed: only the touched roots, and the full lists the
        /// current endpoint returns for all four seminars.
        @Test("A small delta per seminar against a fully seeded store")
        func warmDeltaOnLargeStore() async throws {
            let shape = PerfGraphShape()
            let fixture = PerfFixture(shape: shape)
            let size = 2

            try await withSQLiteStack { stack in
                let seedStart = ContinuousClock.now
                for payload in fixture.payloads() {
                    try await write(payload, using: stack.importer)
                }
                let seed = PerfReport.seconds(seedStart.duration(to: .now))
                let seeded = try await rowCounts(in: stack)

                let deltas = (0..<shape.seminars).map {
                    fixture.delta(seminarIndex: $0, size: size)
                }

                // One request per seminar, carrying only what actually changed.
                let upsertStart = ContinuousClock.now
                for delta in deltas {
                    try await write(
                        SeminarPayload(seminarId: delta.seminarId, dtos: delta.upserted),
                        using: stack.importer
                    )
                }
                let upsert = PerfReport.seconds(upsertStart.duration(to: .now))

                // `upsert` never deletes roots missing from a payload, so a dropped
                // appointment needs an explicit removal. Owned children cascade.
                let deleteStart = ContinuousClock.now
                var deleted = 0
                for delta in deltas {
                    deleted += try await stack.importer.transaction { context in
                        let roots = try CoreDataStorage(context: context).existing(
                            ids: delta.removedIds,
                            identifiedBy: AppointmentEntity.identity
                        )
                        roots.values.forEach(context.delete)
                        return roots.count
                    }
                }
                let delete = PerfReport.seconds(deleteStart.duration(to: .now))

                // The same change as the current endpoint delivers it: every root
                // of every seminar, of which only the delta actually differs.
                let refreshStart = ContinuousClock.now
                for delta in deltas {
                    try await write(
                        SeminarPayload(seminarId: delta.seminarId, dtos: delta.fullList),
                        using: stack.importer
                    )
                }
                let refresh = PerfReport.seconds(refreshStart.duration(to: .now))

                // The opposite end of the warm path: the same full lists, but this
                // time every root, attendee and custom value differs from the store.
                let rewriteStart = ContinuousClock.now
                for seminarIndex in 0..<shape.seminars {
                    try await write(
                        SeminarPayload(
                            seminarId: 3_000 + seminarIndex,
                            dtos: fixture.fullList(
                                seminarIndex: seminarIndex,
                                size: size
                            ) { _ in 2 }
                        ),
                        using: stack.importer
                    )
                }
                let rewrite = PerfReport.seconds(rewriteStart.duration(to: .now))

                // Equal numbers of roots arrived and left in every seminar, so no
                // table may change size; a missed delete or a duplicated insert
                // shows up here.
                let after = try await rowCounts(in: stack)
                #expect(deleted == deltas.reduce(0) { $0 + $1.removedIds.count })
                #expect(after == seeded)

                let touched = deltas.flatMap { $0.changedIds + $0.addedIds }
                let summaries = try await stack.importer.read(touched) { ids, storage in
                    let roots = try storage.existing(
                        ids: ids,
                        identifiedBy: AppointmentEntity.identity,
                        prefetching: [#keyPath(AppointmentEntity.topics)]
                    )
                    let mapper = AppointmentEntityMapper()
                    return try ids.compactMap { try roots[$0].map(mapper.map) }
                }
                // The last write rewrote every surviving root to revision 2.
                #expect(summaries.map(\.id) == touched)
                #expect(summaries.allSatisfy { $0.name.hasSuffix("r2") })
                let survivors = try await stack.importer.read(
                    deltas.flatMap(\.removedIds)
                ) { ids, storage in
                    Array(
                        try storage.existing(
                            ids: ids,
                            identifiedBy: AppointmentEntity.identity
                        ).keys
                    )
                }
                #expect(survivors.isEmpty)

                let seededRoots = shape.seminars * shape.appointmentsPerSeminar
                PerfReport.print(
                    """
                    warm delta on \(seededRoots) seeded roots, \(size) edited + \
                    \(size) added + \(size) removed per seminar, \
                    batch \(CoreDataImporter.defaultBatchSize)
                    """,
                    shape: shape,
                    samples: [
                        PerfSample(
                            label: "seed every seminar (cold)",
                            roots: seededRoots,
                            seconds: seed
                        ),
                        PerfSample(
                            label: "delta upsert, \(shape.seminars) seminars",
                            roots: shape.seminars * 2 * size,
                            seconds: upsert
                        ),
                        PerfSample(
                            label: "delete, \(shape.seminars) seminars",
                            roots: shape.seminars * size,
                            seconds: delete
                        ),
                        PerfSample(
                            label: "full-list refresh, \(shape.seminars) seminars",
                            roots: seededRoots,
                            seconds: refresh
                        ),
                        PerfSample(
                            label: "full-list rewrite, every root changed",
                            roots: seededRoots,
                            seconds: rewrite
                        )
                    ]
                )
            }
        }

        /// Batch size trades transaction count against per-batch graph size. Each
        /// point runs the same three stages on its own store, because the curve
        /// differs between inserting rows and re-saving rows already there.
        @Test("Batch size sweep, cold then warm",
              arguments: [100, 250, 500, 1_000, 2_000, 4_000])
        func batchSizeSweep(batchSize: Int) async throws {
            var shape = PerfGraphShape()
            shape.seminars = 1
            let fixture = PerfFixture(shape: shape)
            let payload = fixture.payload(seminarIndex: 0)
            let roots = payload.dtos.count

            func list(revision: Int) -> SeminarPayload {
                SeminarPayload(
                    seminarId: payload.seminarId,
                    dtos: fixture.fullList(seminarIndex: 0, size: 0) { _ in revision }
                )
            }

            try await withSQLiteStack { stack in
                let coldStart = ContinuousClock.now
                try await write(payload, using: stack.importer, batchSize: batchSize)
                let cold = PerfReport.seconds(coldStart.duration(to: .now))

                // The common refresh: every root is fetched and compared, none differ.
                let unchangedStart = ContinuousClock.now
                try await write(list(revision: 0), using: stack.importer, batchSize: batchSize)
                let unchanged = PerfReport.seconds(unchangedStart.duration(to: .now))

                // The demanding refresh: every root, attendee and value differs.
                let changedStart = ContinuousClock.now
                try await write(list(revision: 1), using: stack.importer, batchSize: batchSize)
                let changed = PerfReport.seconds(changedStart.duration(to: .now))

                PerfReport.print(
                    "batch \(batchSize)",
                    shape: shape,
                    samples: [
                        PerfSample(label: "cold insert", roots: roots, seconds: cold),
                        PerfSample(label: "warm, nothing changed", roots: roots, seconds: unchanged),
                        PerfSample(label: "warm, everything changed", roots: roots, seconds: changed)
                    ]
                )
            }
        }

        // MARK: Helpers

        private func runMixedRequests(
            mode: MixedImportMode,
            phase: String,
            client: DefaultAPIClient,
            stack: CoreDataStack
        ) async throws -> [PerfSample] {
            let requests = MixedRequest.allCases
            let importer = stack.importer
            let totalStart = ContinuousClock.now
            var samples: [PerfSample] = []
            switch mode {
            case .sequentialShared:
                for request in requests {
                    let start = ContinuousClock.now
                    let count = try await request.execute(client: client, importer: importer)
                    #expect(count == request.expectedCount)
                    samples.append(PerfSample(
                        label: "\(phase) \(request.rawValue)", roots: count,
                        seconds: PerfReport.seconds(start.duration(to: .now))
                    ))
                }
            case .concurrentShared:
                let results = try await withThrowingTaskGroup(
                    of: (MixedRequest, PerfSample).self
                ) { group in
                    for request in requests {
                        group.addTask {
                            let start = ContinuousClock.now
                            let count = try await request.execute(client: client, importer: importer)
                            return (request, PerfSample(
                                label: "\(phase) \(request.rawValue)", roots: count,
                                seconds: PerfReport.seconds(start.duration(to: .now))
                            ))
                        }
                    }
                    var results: [(MixedRequest, PerfSample)] = []
                    for try await result in group { results.append(result) }
                    return results
                }
                for (request, sample) in results {
                    #expect(sample.roots == request.expectedCount)
                }
                samples = results.map(\.1).sorted { $0.label < $1.label }
            }
            samples.append(PerfSample(
                label: "\(phase) TOTAL wall clock",
                roots: requests.reduce(0) { $0 + $1.expectedCount },
                seconds: PerfReport.seconds(totalStart.duration(to: .now))
            ))
            return samples
        }

        private func expectMixedCounts(in stack: CoreDataStack) async throws {
            let counts = try await stack.importer.transaction { context in
                var counts: [String: Int] = [:]
                for request in MixedRequest.allCases {
                    counts[request.entityName] = try context.count(
                        for: NSFetchRequest<NSManagedObject>(entityName: request.entityName)
                    )
                }
                counts["ScheduleReservationEntity"] = try context.count(
                    for: NSFetchRequest<NSManagedObject>(entityName: "ScheduleReservationEntity")
                )
                return counts
            }
            for request in MixedRequest.allCases {
                #expect(counts[request.entityName] == request.expectedCount)
            }
            #expect(counts["ScheduleReservationEntity"] == 2_238)
        }

        /// Mirrors `AppointmentRepositoryImpl`: normalize the whole response, then
        /// commit it in bounded root batches through the given importer.
        private func write(
            _ payload: SeminarPayload,
            using importer: CoreDataImporter,
            batchSize: Int = CoreDataImporter.defaultBatchSize
        ) async throws {
            let mapper = AppointmentEntityMapper()
            let snapshots = mapper.latestSnapshots(in: payload.dtos)
            try await importer.write(snapshots, batchSize: batchSize) { batch, storage in
                _ = try mapper.upsert(batch, using: storage)
            }
        }

        private func rowCounts(in stack: CoreDataStack) async throws -> [String: Int] {
            try await stack.importer.transaction { context in
                var counts: [String: Int] = [:]
                for name in [
                    "AppointmentEntity",
                    "AppointmentAttendeeEntity",
                    "CustomFieldEntity",
                    "CustomFieldValueEntity"
                ] {
                    counts[name] = try context.count(
                        for: NSFetchRequest<NSManagedObject>(entityName: name)
                    )
                }
                return counts
            }
        }

        private func expectRowCounts(
            _ shape: PerfGraphShape,
            in stack: CoreDataStack
        ) async throws {
            let counts = try await rowCounts(in: stack)
            #expect(counts["AppointmentEntity"] == shape.seminars * shape.rootsPerSeminar)
            #expect(
                counts["AppointmentAttendeeEntity"] == shape.seminars * shape.attendeeRowsPerSeminar
            )
            #expect(
                counts["CustomFieldEntity"] == shape.seminars * shape.customFieldRowsPerSeminar
            )
            #expect(
                counts["CustomFieldValueEntity"] == shape.seminars * shape.customValueRowsPerSeminar
            )
        }

        private func withSQLiteStack(
            _ operation: (CoreDataStack) async throws -> Void
        ) async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }

            let stack = try CoreDataStack(
                storage: .persistent,
                storeURL: directory.appendingPathComponent("Performance.sqlite")
            )
            try await stack.load()
            defer {
                let coordinator = stack.persistentContainer.persistentStoreCoordinator
                for store in coordinator.persistentStores {
                    try? coordinator.remove(store)
                }
            }
            try await operation(stack)
        }
    }
}
