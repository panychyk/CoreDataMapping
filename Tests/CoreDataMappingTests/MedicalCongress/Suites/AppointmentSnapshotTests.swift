import Testing

@MainActor
@Suite("Medical congress · appointment snapshot")
struct AppointmentSnapshotTests {
    @Test("Removing a meeting deletes its participants")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].appointments.remove(at: 0)
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        #expect(try stack.count(Person.self) == 3)
        #expect(try stack.count(Room.self) == 2)
    }
}
