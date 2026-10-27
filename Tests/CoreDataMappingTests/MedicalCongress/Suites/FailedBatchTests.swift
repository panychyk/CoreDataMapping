import Testing

@MainActor
@Suite("Medical congress · failed batch")
struct FailedBatchTests {
    @Test("A failed second batch retains the first committed event")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        enum ExpectedFailure: Error { case secondBatch }
        let full = GraphCases.congress()
        var first = full
        first.events = [full.events[0]]
        var second = full
        second.events = [full.events[1]]
        do {
            try await stack.importer.write([first, second], batchSize: 1) { batch, storage in
                try GraphWriter.write(batch, using: storage)
                if batch[0].events[0].id == 41 { throw ExpectedFailure.secondBatch }
            }
            Issue.record("The second batch should fail")
        } catch ExpectedFailure.secondBatch {}
        try GraphAssertions.matches(first, in: stack)
    }
}
