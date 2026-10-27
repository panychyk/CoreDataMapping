import Testing

@MainActor
@Suite("Medical congress · shared person")
struct SharedPersonTests {
    @Test("Shared person survives an appointment change")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].appointments[0].participants.removeAll { $0.personID == 10 }
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let person = try #require(stack.fetch(Person.self).first { $0.id == 10 })
        #expect(person.appointments?.count == 2)
        #expect(person.registrations?.count == 2)
    }
}
