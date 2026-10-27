import Testing

@MainActor
@Suite("Medical congress · participant snapshot")
struct ParticipantSnapshotTests {
    @Test("Replacing participants deletes only surplus join rows")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].appointments[0].participants = [
            .init(personID: 11, status: "confirmed"),
            .init(personID: 12, status: "arrived"),
        ]
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        #expect(try stack.count(Person.self) == 3)
    }
}
