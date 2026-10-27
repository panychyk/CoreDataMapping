import Testing

@MainActor
@Suite("Medical congress · concurrent imports")
struct ConcurrentImportsTests {
    @Test("One importer serializes concurrent event writes")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let graph = GraphCases.congress()
        let importer = stack.importer
        try await withThrowingTaskGroup(of: Void.self) { group in
            for event in graph.events {
                var partial = graph
                partial.events = [event]
                group.addTask {
                    try await importer.write([partial]) { batch, storage in
                        try GraphWriter.write(batch, using: storage)
                    }
                }
            }
            try await group.waitForAll()
        }
        try GraphAssertions.matches(graph, in: stack)
    }
}
