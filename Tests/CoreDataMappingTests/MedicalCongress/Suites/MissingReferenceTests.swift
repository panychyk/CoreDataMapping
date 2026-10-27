import Testing

@MainActor
@Suite("Medical congress · missing reference")
struct MissingReferenceTests {
    @Test("A missing shared room rolls back the whole update")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = GraphCases.congress()
        try await stack.write(original)

        var invalid = original
        invalid.events[0].appointments[0].roomID = 999
        await #expect(throws: GraphFixtureError.missingReference(entity: "Room", id: 999)) {
            try await stack.write(invalid)
        }
        try GraphAssertions.matches(original, in: stack)
    }
}
