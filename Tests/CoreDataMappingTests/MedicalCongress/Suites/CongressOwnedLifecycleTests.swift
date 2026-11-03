import CoreData
import Testing

/// Verifies removal of rows owned by a removed part of the congress. People,
/// rooms, and resources used elsewhere remain available.
///
/// - `participantSnapshot`: surplus participation rows disappear; people remain.
/// - `appointmentSnapshot`: removing an appointment deletes its participation
///   rows while preserving people and rooms.
/// - `sessionSnapshot`: removing a session deletes speaker rows while preserving
///   people and resources.
/// - `registrationSnapshot`: removing a registration deletes its check-in and
///   preserves the person.
/// - `eventDeletion`: cascade deletion removes an event's child graph and
///   preserves shared entities.
@MainActor
@Suite("Medical congress · owned lifecycle")
struct CongressOwnedLifecycleTests {
    @Test("Replacing participants deletes only surplus join rows")
    func participantSnapshot() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].appointments[0].participants = [
            .init(personID: 11, status: "confirmed"),
            .init(personID: 12, status: "arrived"),
        ]
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        #expect(try stack.count(Person.self) == 3)
    }

    @Test("Removing a meeting deletes its participants")
    func appointmentSnapshot() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].appointments.remove(at: 0)
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        #expect(try stack.count(Person.self) == 3)
        #expect(try stack.count(Room.self) == 2)
    }

    @Test("Removing a session deletes speaker joins but preserves resources")
    func sessionSnapshot() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].tracks[0].sessions.removeAll()
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        #expect(try stack.count(ResourceAsset.self) == 2)
        #expect(try stack.count(Person.self) == 3)
    }

    @Test("Removing a registration deletes its check-ins only")
    func registrationSnapshot() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].registrations.removeAll { $0.personID == 10 }
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let person = try #require(stack.fetch(Person.self).first { $0.id == 10 })
        #expect(person.registrations?.count == 1)
    }

    @Test("Deleting an event cascades owned rows and keeps shared rows")
    func eventDeletion() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        try await stack.importer.transaction { context in
            let request = NSFetchRequest<CongressEvent>(entityName: "CongressEvent")
            guard let event = try context.fetch(request).first(where: { $0.id == 40 }) else {
                throw GraphFixtureError.missingReference(entity: "CongressEvent", id: 40)
            }
            context.delete(event)
        }
        var remaining = initial
        remaining.events.remove(at: 0)
        try GraphAssertions.matches(remaining, in: stack)
        #expect(try stack.count(Person.self) == 3)
        #expect(try stack.count(ResourceAsset.self) == 2)
    }
}
