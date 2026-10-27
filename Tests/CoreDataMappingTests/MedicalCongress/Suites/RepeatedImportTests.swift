import Testing

@MainActor
@Suite("Medical congress · repeated import")
struct RepeatedImportTests {
    @Test("Repeated full snapshots reuse rows")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        let before = Set(try stack.fetch(Appointment.self).map { $0.objectID })
        try await stack.write(initial)
        try GraphAssertions.matches(initial, in: stack)
        let after = Set(try stack.fetch(Appointment.self).map { $0.objectID })
        #expect(before == after)
    }
}
