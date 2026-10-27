import Testing

@MainActor
@Suite("Medical congress · session snapshot")
struct SessionSnapshotTests {
    @Test("Removing a session deletes speaker joins but preserves resources")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].tracks[0].sessions.removeAll()
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        #expect(try stack.count(ResourceAsset.self) == 2)
        #expect(try stack.count(Person.self) == 3)
    }
}
