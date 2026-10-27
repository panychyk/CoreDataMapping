import Testing

@MainActor
@Suite("Medical congress · shared resource")
struct SharedResourceTests {
    @Test("Removing a session resource preserves its other use")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].tracks[0].sessions[0].resourceIDs = [31]
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let resource = try #require(stack.fetch(ResourceAsset.self).first { $0.id == 30 })
        #expect(resource.sessions?.count == 1)
    }
}
