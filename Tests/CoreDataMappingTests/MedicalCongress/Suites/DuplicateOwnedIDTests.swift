import CoreDataMapping
import Testing

@MainActor
@Suite("Medical congress · duplicate owned ID")
struct DuplicateOwnedIDTests {
    @Test("Duplicate appointment IDs reject the batch and preserve the saved graph")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let original = GraphCases.congress()
        try await stack.write(original)
        var invalid = original
        invalid.events[0].appointments.append(invalid.events[0].appointments[0])
        await #expect(
            throws: CoreDataStorageError.duplicateOwnedIdentity(
                entityName: "Appointment", id: "1"
            )
        ) {
            try await stack.write(invalid)
        }
        try GraphAssertions.matches(original, in: stack)
    }
}
