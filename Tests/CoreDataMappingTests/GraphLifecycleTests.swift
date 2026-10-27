import CoreData
import CoreDataMapping
import Testing

@MainActor
@Suite("Graph lifecycle and SQLite persistence")
struct GraphLifecycleTests {
    @Test("Full snapshots preserve every relationship and only remove owned rows")
    func fullSnapshotReconcilesSectionsAndKeepsResources() async throws {
        let stack = try CoreDataTestStack()
        try await stack.load()
        let initial = GraphCases.roots(perKind: 2)
        try await stack.writeGraph(initial)
        try GraphAssertions.matches(initial, in: stack)

        let originalDocument = initial[0]
        let updatedDocument = RootSnapshot(
            kind: .document, id: originalDocument.id, title: "updated",
            resourceIDs: [2, 3], sections: [originalDocument.sections[1]]
        )
        try await stack.writeGraph([updatedDocument])
        var expected = initial
        expected[0] = updatedDocument
        try GraphAssertions.matches(expected, in: stack)

        let resources = try stack.fetch(Resource.self)
        let resource = try #require(resources.first { $0.id == 1 })
        #expect(resource.documents?.count == 1)
        #expect(resource.folders?.count == 2)
        #expect(resource.dashboards?.count == 0)
        #expect(resources.first { $0.id == 3 }?.dashboards?.count == 2)
        #expect(resource.boards?.count == 2)
        #expect(resource.workspaces?.count == 2)
    }

    @Test("Repeated writes reuse rows and SQLite reopens with the same graph")
    func repeatedImportReusesSectionsAfterSQLiteReopen() async throws {
        let store = try TemporarySQLiteStore()
        defer { store.remove() }
        let first = try CoreDataTestStack(sqliteURL: store.url)
        try await first.load()
        let values = GraphCases.roots(perKind: 6)
        try await first.writeGraph(values, batchSize: 4)
        let before = Set(try first.fetch(Section.self).map { $0.objectID.uriRepresentation() })
        try await first.writeGraph(values, batchSize: 4)
        try GraphAssertions.matches(values, in: first)
        let after = Set(try first.fetch(Section.self).map { $0.objectID.uriRepresentation() })
        #expect(after == before)

        let reopened = try CoreDataTestStack(sqliteURL: store.url)
        try await reopened.load()
        try GraphAssertions.matches(values, in: reopened)
    }

    @Test("Deleting a board cascades through sections and entries while preserving resources")
    func deletingBoardCascadesOnlyOwnedRows() async throws {
        let stack = try CoreDataTestStack()
        try await stack.load()
        let values = GraphCases.roots(perKind: 1)
        try await stack.writeGraph(values)
        try await stack.importer.transaction { context in
            let board = try context.fetch(NSFetchRequest<Board>(entityName: "Board")).first!
            context.delete(board)
        }
        try GraphAssertions.matches(values.filter { $0.kind != .board }, in: stack)
    }
}
