import Testing

/// Перевіряє, що зміна учасників, кімнат, матеріалів чи спонсорів в одній
/// події не порушує їхнього використання в інших подіях.
///
/// - `sharedPerson`: вилучення з однієї зустрічі зберігає інші зустрічі й реєстрації.
/// - `sharedRoom`: перенесення зустрічі не змінює інші бронювання кімнати.
/// - `sharedResource`: відв’язування матеріалу зберігає його в іншій сесії.
/// - `sponsorSnapshot`: вилучення спонсорства зберігає організацію та її
///   спонсорство другої події.
@MainActor
@Suite("Medical congress · shared relationships")
struct CongressSharedRelationshipsTests {
    @Test("Shared person survives an appointment change")
    func sharedPerson() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].appointments[0].participants.removeAll { $0.personID == 10 }
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let person = try #require(stack.fetch(Person.self).first { $0.id == 10 })
        #expect(person.appointments?.count == 2)
        #expect(person.registrations?.count == 2)
    }

    @Test("Changing one meeting room keeps other bookings")
    func sharedRoom() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].appointments[0].roomID = 21
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let room = try #require(stack.fetch(Room.self).first { $0.id == 22 })
        #expect(room.appointments?.count == 2)
    }

    @Test("Removing a session resource preserves its other use")
    func sharedResource() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].tracks[0].sessions[0].resourceIDs = [31]
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let resource = try #require(stack.fetch(ResourceAsset.self).first { $0.id == 30 })
        #expect(resource.sessions?.count == 1)
    }

    @Test("Removing a sponsorship keeps the organization")
    func sponsorSnapshot() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].sponsorIDs = []
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let sponsor = try #require(stack.fetch(Organization.self).first { $0.id == 2 })
        #expect(sponsor.sponsorships?.count == 1)
    }
}
