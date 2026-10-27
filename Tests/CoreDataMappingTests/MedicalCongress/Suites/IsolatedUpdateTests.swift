import Testing

@MainActor
@Suite("Medical congress · isolated update")
struct IsolatedUpdateTests {
    @Test("Updating one event preserves the other event")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].title = "Research Day revised"
        graph.events[0].tracks[0].sessions[0].title = "Updated therapies"
        graph.events[0].appointments[0].participants[0].status = "arrived"
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
    }
}
