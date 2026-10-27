import Testing

@MainActor
@Suite("Medical congress · registration snapshot")
struct RegistrationSnapshotTests {
    @Test("Removing a registration deletes its check-ins only")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].registrations.removeAll { $0.personID == 10 }
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let person = try #require(stack.fetch(Person.self).first { $0.id == 10 })
        #expect(person.registrations?.count == 1)
    }
}
