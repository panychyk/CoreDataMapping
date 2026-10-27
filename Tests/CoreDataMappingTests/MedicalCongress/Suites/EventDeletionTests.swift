import CoreData
import Testing

@MainActor
@Suite("Medical congress · event deletion")
struct EventDeletionTests {
    @Test("Deleting an event cascades owned rows and keeps shared rows")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        try await stack.importer.transaction { context in
            let request = NSFetchRequest<CongressEvent>(entityName: "CongressEvent")
            guard let event = try context.fetch(request).first(where: { $0.id == 40 }) else {
                throw GraphFixtureError.missingReference(entity: "CongressEvent", id: 40)
            }
            context.delete(event)
        }
        var remaining = initial
        remaining.events.remove(at: 0)
        try GraphAssertions.matches(remaining, in: stack)
        #expect(try stack.count(Person.self) == 3)
        #expect(try stack.count(ResourceAsset.self) == 2)
    }
}
