import CoreData
import Testing

/// Перевіряє, що після вилучення частини конгресу зникають пов’язані з нею
/// записи. Люди, кімнати й матеріали, які використовуються деінде,
/// залишаються доступними.
///
/// - `participantSnapshot`: зайві записи участі зникають, люди залишаються.
/// - `appointmentSnapshot`: вилучення зустрічі видаляє записи участі та зберігає
///   людей і кімнати.
/// - `sessionSnapshot`: вилучення сесії видаляє записи спікерів та зберігає
///   людей і матеріали.
/// - `registrationSnapshot`: вилучення реєстрації видаляє її check-in та зберігає людину.
/// - `eventDeletion`: каскадне видалення прибирає дочірній граф події та зберігає
///   спільні сутності.
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
