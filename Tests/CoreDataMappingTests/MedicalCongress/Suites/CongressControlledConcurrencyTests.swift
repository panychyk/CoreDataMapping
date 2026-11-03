import CoreDataMapping
import Testing

/// Verifies visibility of committed snapshots and ordering of concurrent writes
/// through one importer. Unsaved changes stay within its context; rollback of
/// one call preserves the previous commit and shared entities.
///
/// - `twoFullSnapshotsExposeOnlyCommittedVersions`: another context sees the
///   initial graph, then the first snapshot, then the second after its commit.
/// - `concurrentEventUpdatesRollbackThenRecover`: overlapping event writes roll
///   back the second while preserving the first, then succeed on retry.
@MainActor
@Suite("Medical congress · controlled concurrent imports")
struct CongressControlledConcurrencyTests {
    @Test("Two full event snapshots become visible only after their commits")
    func twoFullSnapshotsExposeOnlyCommittedVersions() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        try GraphAssertions.matches(initial, in: stack)
        let originalEventID = try #require(stack.fetch(CongressEvent.self).first {
            $0.id == 40
        }).objectID
        let originalTrackID = try #require(stack.fetch(Track.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }).objectID
        let originalAppointmentID = try #require(stack.fetch(Appointment.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }).objectID

        var first = initial
        first.events = [initial.events[0]]
        first.events[0].title = "Research A"
        first.events[0].tracks[0].sessions[0].roomID = 22
        first.events[0].tracks[0].sessions[0].speakerIDs = [10]
        first.events[0].tracks[0].sessions[0].resourceIDs = [31]
        first.events[0].tracks[0].sessions.append(
            .init(id: 2, title: "A-only session", roomID: 21,
                  speakerIDs: [11], resourceIDs: [30])
        )
        first.events[0].appointments.swapAt(0, 1)
        first.events[0].appointments[1].participants.removeAll { $0.personID == 10 }
        first.events[0].registrations[0].checkInIDs.append(2)
        first.events[0].sponsorIDs = []
        var afterFirst = initial
        afterFirst.events[0] = first.events[0]

        var second = initial
        second.events = [initial.events[0]]
        second.events[0].title = "Research B"
        second.events[0].tracks[0].sessions[0].title = "B final session"
        second.events[0].tracks[0].sessions[0].speakerIDs = [12, 10]
        second.events[0].tracks[0].sessions[0].resourceIDs = [30]
        second.events[0].appointments = [
            .init(id: 1, title: "Meeting B", roomID: 21,
                  participants: [.init(personID: 11, status: "confirmed")])
        ]
        second.events[0].registrations = [
            .init(personID: 10, status: "checked in B", checkInIDs: [2])
        ]
        second.events[0].sponsorIDs = [1]
        var afterSecond = initial
        afterSecond.events[0] = second.events[0]

        let firstGate = ControlledImportGate()
        let secondGate = ControlledImportGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
        let importer = stack.importer
        let firstTask = Task {
            try await importer.write([first]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                try firstGate.pauseAfterMapping()
            }
        }
        try await firstGate.waitUntilMapped()

        let secondTask = Task {
            secondGate.signalStarted()
            try await importer.write([second]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                try secondGate.pauseAfterMapping()
            }
        }
        try await secondGate.waitUntilStarted()
        try GraphAssertions.matches(initial, in: stack)
        firstGate.release()

        try await secondGate.waitUntilMapped()
        try await firstTask.value
        try GraphAssertions.matches(afterFirst, in: stack)
        #expect(try stack.fetch(CongressEvent.self).first { $0.id == 40 }?.objectID == originalEventID)
        #expect(try stack.fetch(Track.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }?.objectID == originalTrackID)
        secondGate.release()

        try await secondTask.value
        try GraphAssertions.matches(afterSecond, in: stack)
        #expect(try stack.fetch(CongressEvent.self).first { $0.id == 40 }?.objectID == originalEventID)
        #expect(try stack.fetch(Appointment.self).first {
            $0.event?.id == 40 && $0.localID == 1
        }?.objectID == originalAppointmentID)
        #expect(try stack.fetch(Session.self).allSatisfy { $0.title != "A-only session" })
        #expect(try stack.fetch(ResourceAsset.self).first { $0.id == 30 }?.sessions?.count == 2)
        #expect(try stack.fetch(Organization.self).first { $0.id == 2 }?.sponsorships?.count == 1)
    }

    @Test("Overlapping event writes keep a committed graph through rollback and retry")
    func concurrentEventUpdatesRollbackThenRecover() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        try GraphAssertions.matches(initial, in: stack)
        let originalEventIDs = Set(try stack.fetch(CongressEvent.self).map(\.objectID))
        let originalSharedIDs = Set(try stack.fetch(Person.self).map(\.objectID))

        var first = initial
        first.events = [initial.events[0]]
        first.organizations[0].name = "Hospital A"
        first.people[0].name = "Person A"
        first.rooms[1].name = "Room A"
        first.resources[0].title = "Resource A"
        first.events[0].title = "Research parallel A"
        first.events[0].tracks[0].sessions[0].roomID = 22
        first.events[0].tracks[0].sessions[0].speakerIDs = [11]
        first.events[0].tracks[0].sessions[0].resourceIDs = [31]
        first.events[0].appointments[0].roomID = 21
        first.events[0].appointments[0].participants = [
            .init(personID: 12, status: "arrived")
        ]
        first.events[0].sponsorIDs = [1]
        var afterFirst = initial
        afterFirst.organizations = first.organizations
        afterFirst.people = first.people
        afterFirst.rooms = first.rooms
        afterFirst.resources = first.resources
        afterFirst.events[0] = first.events[0]

        var second = first
        second.events = [initial.events[1]]
        second.organizations[1].name = "Organization B"
        second.resources[1].title = "Resource B"
        second.events[0].title = "Clinical parallel B"
        second.events[0].tracks[0].sessions[0].roomID = 22
        second.events[0].tracks[0].sessions[0].speakerIDs = [10, 12]
        second.events[0].tracks[0].sessions[0].resourceIDs = [30, 31]
        second.events[0].appointments[0].roomID = 21
        second.events[0].appointments[0].participants = [
            .init(personID: 10, status: "confirmed"),
            .init(personID: 12, status: "arrived"),
        ]
        second.events[0].appointments.append(
            .init(id: 2, title: "Second event meeting", roomID: 22,
                  participants: [.init(personID: 11, status: "invited")])
        )
        second.events[0].registrations[1].checkInIDs = [1]
        second.events[0].sponsorIDs = [1, 2]
        var completed = afterFirst
        completed.organizations = second.organizations
        completed.resources = second.resources
        completed.events[1] = second.events[0]

        let firstGate = ControlledImportGate()
        let secondGate = ControlledImportGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
        let importer = stack.importer
        let firstTask = Task {
            try await importer.write([first]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                try firstGate.pauseAfterMapping()
            }
        }
        try await firstGate.waitUntilMapped()

        let secondTask = Task {
            secondGate.signalStarted()
            try await importer.write([second]) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                try secondGate.pauseAfterMapping()
                throw ControlledImportFailure.afterMapping
            }
        }
        try await secondGate.waitUntilStarted()
        try GraphAssertions.matches(initial, in: stack)
        firstGate.release()

        try await secondGate.waitUntilMapped()
        try await firstTask.value
        try GraphAssertions.matches(afterFirst, in: stack)
        secondGate.release()

        await #expect(throws: ControlledImportFailure.afterMapping) {
            try await secondTask.value
        }
        try GraphAssertions.matches(afterFirst, in: stack)
        #expect(try stack.fetch(ResourceAsset.self).first { $0.id == 31 }?.title == "Clinical results")
        #expect(try stack.fetch(Organization.self).first { $0.id == 2 }?.name == "Nova Therapeutics")

        try await stack.write(second)
        try GraphAssertions.matches(completed, in: stack)
        #expect(Set(try stack.fetch(CongressEvent.self).map(\.objectID)) == originalEventIDs)
        #expect(Set(try stack.fetch(Person.self).map(\.objectID)) == originalSharedIDs)
        #expect(try stack.fetch(Appointment.self).filter { $0.localID == 2 }.count == 2)
    }
}

private enum ControlledImportFailure: Error, Equatable {
    case afterMapping
}
