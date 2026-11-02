import CoreDataMapping
import Testing

/// Перевіряє складні переходи повного графа конгресу: перестановку та
/// узгодження вкладених дітей, повторні локальні ID у різних власників і
/// відкат пізньої помилки без втрати вже збереженої порції.
///
/// - `multilevelSnapshot`: одночасна зміна shared-зв’язків і кількох рівнів
///   owned-дітей зберігає identity незмінених записів та іншу подію.
/// - `lateFailureAndRetry`: помилка в кінці другої порції відкочує всі її
///   зміни; повторний коректний імпорт завершує граф без дублікатів.
@MainActor
@Suite("Medical congress · complex graph transitions")
struct CongressComplexTransitionsTests {
    @Test("A multilevel snapshot reorders and reconciles children without mixing owners")
    func multilevelSnapshot() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)

        stack.resetViewContext()
        let originalTrack = try #require(stack.fetch(Track.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }).objectID
        let originalSession = try #require(stack.fetch(Session.self).first {
            $0.track?.event?.id == 40 && $0.localID == 1
        }).objectID
        let originalAppointment = try #require(stack.fetch(Appointment.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }).objectID
        let untouchedEvent = try #require(stack.fetch(CongressEvent.self).first {
            $0.id == 41
        }).objectID

        var changed = initial
        changed.people[0].organizationID = 2
        changed.resources[0].title = "Revised oncology overview"
        changed.events[0].tracks[0].title = "Research revised"
        changed.events[0].tracks[0].sessions[0].title = "New therapies revised"
        changed.events[0].tracks[0].sessions[0].roomID = 22
        changed.events[0].tracks[0].sessions[0].speakerIDs = [12, 10]
        changed.events[0].tracks[0].sessions[0].resourceIDs = [31]
        changed.events[0].tracks[0].sessions.insert(
            .init(id: 2, title: "New evidence", roomID: 21,
                  speakerIDs: [11], resourceIDs: [30]), at: 0
        )
        changed.events[0].tracks.append(
            .init(id: 2, title: "Practice", sessions: [
                .init(id: 1, title: "Case studies", roomID: 22,
                      speakerIDs: [10], resourceIDs: [30])
            ])
        )
        changed.events[0].appointments.swapAt(0, 1)
        changed.events[0].appointments[0].title = "Follow-up revised"
        changed.events[0].appointments[1].participants = [
            .init(personID: 12, status: "arrived"),
            .init(personID: 11, status: "invited"),
        ]
        changed.events[0].appointments.append(
            .init(id: 3, title: "New meeting", roomID: 21,
                  participants: [.init(personID: 10, status: "confirmed")])
        )
        changed.events[0].registrations = [
            .init(personID: 10, status: "checked in", checkInIDs: [2, 1]),
            .init(personID: 12, status: "registered", checkInIDs: [1]),
        ]
        changed.events[0].sponsorIDs = []

        try await stack.write(changed)
        try GraphAssertions.matches(changed, in: stack)
        #expect(try stack.fetch(Track.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }?.objectID == originalTrack)
        #expect(try stack.fetch(Session.self).first {
            $0.track?.event?.id == 40 && $0.track?.localID == 1 && $0.localID == 1
        }?.objectID == originalSession)
        #expect(try stack.fetch(Appointment.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }?.objectID == originalAppointment)
        #expect(try stack.fetch(CongressEvent.self).first { $0.id == 41 }?.objectID == untouchedEvent)

        // The same local session ID now exists under three distinct tracks.
        #expect(try stack.fetch(Session.self).filter { $0.localID == 1 }.count == 3)
        #expect(try stack.fetch(Registration.self).filter { $0.localID == 12 }.count == 2)
    }

    @Test("A late error rolls back the second batch and a retry completes the graph")
    func lateFailureAndRetry() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)

        stack.resetViewContext()
        let eventID = try #require(stack.fetch(CongressEvent.self).first { $0.id == 41 }).objectID
        let sessionID = try #require(stack.fetch(Session.self).first {
            $0.track?.event?.id == 41
        }).objectID

        var committed = initial
        committed.events = [initial.events[0]]
        committed.events[0].title = "Research Day committed"
        committed.events[0].tracks[0].sessions[0].title = "Committed therapies"
        committed.events[0].appointments[0].participants[0].status = "arrived"

        var second = initial
        second.events = [initial.events[1]]
        second.organizations[0].name = "Uncommitted hospital name"
        second.people[0].name = "Uncommitted person name"
        second.events[0].tracks[0].sessions[0].title = "Clinical update"
        second.events[0].tracks[0].sessions[0].speakerIDs = [11, 12]
        second.events[0].appointments[0].participants = [
            .init(personID: 12, status: "confirmed")
        ]
        second.events[0].registrations[0].checkInIDs = [1, 2]
        second.events[0].sponsorIDs = [2, 999]

        await #expect(throws: GraphFixtureError.missingReference(entity: "Organization", id: 999)) {
            try await stack.importer.write([committed, second], batchSize: 1) { batch, storage in
                try GraphWriter.write(batch, using: storage)
            }
        }
        var afterFailure = initial
        afterFailure.events[0] = committed.events[0]
        try GraphAssertions.matches(afterFailure, in: stack)
        #expect(try stack.fetch(CongressEvent.self).first { $0.id == 41 }?.objectID == eventID)
        #expect(try stack.fetch(Session.self).first {
            $0.track?.event?.id == 41
        }?.objectID == sessionID)

        second.events[0].sponsorIDs = [1, 2]
        try await stack.write(second)
        var completed = afterFailure
        completed.organizations = second.organizations
        completed.people = second.people
        completed.events[1] = second.events[0]
        try GraphAssertions.matches(completed, in: stack)
        #expect(try stack.fetch(CongressEvent.self).first { $0.id == 41 }?.objectID == eventID)
        #expect(try stack.fetch(Session.self).first {
            $0.track?.event?.id == 41
        }?.objectID == sessionID)
    }
}
