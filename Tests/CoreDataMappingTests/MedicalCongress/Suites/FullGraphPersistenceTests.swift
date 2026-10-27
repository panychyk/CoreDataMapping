import Testing

@MainActor
@Suite("Medical congress · full graph persistence")
struct FullGraphPersistenceTests {
    @Test("A full congress graph survives a context reset")
    func fullGraphSurvivesContextReset() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let graph = GraphCases.congress()

        try await stack.write(graph)

        try GraphAssertions.matches(graph, in: stack)
    }
}
