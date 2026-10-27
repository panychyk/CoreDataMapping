import Testing

@MainActor
@Suite("Medical congress · sequential imports")
struct SequentialImportsTests {
    @Test("Two committed imports assemble the full congress")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let complete = GraphCases.congress()
        var first = complete
        first.events = [complete.events[0]]
        try await stack.write(first)
        try GraphAssertions.matches(first, in: stack)
        var second = complete
        second.events = [complete.events[1]]
        try await stack.write(second)
        try GraphAssertions.matches(complete, in: stack)
    }
}
