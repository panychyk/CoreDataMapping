import CoreData
import CoreDataMapping
import Testing

@MainActor
@Suite("Concurrent graph imports")
struct GraphConcurrencyTests {
    @Test("Five concurrent imports persist large independent roots and shared resources")
    func oneImporterSerializesConcurrentLargeImports() async throws {
        let store = try TemporarySQLiteStore()
        defer { store.remove() }
        let stack = try CoreDataTestStack(sqliteURL: store.url)
        try await stack.load()
        let values = GraphCases.roots(perKind: 251)
        let importer = stack.importer
        try await withThrowingTaskGroup(of: Void.self) { group in
            for kind in RootKind.allCases {
                let groupValues = values.filter { $0.kind == kind }
                group.addTask {
                    try await importer.write(groupValues, batchSize: 37) { batch, storage in
                        try GraphWriter.write(batch, using: storage)
                    }
                }
            }
            try await group.waitForAll()
        }
        try GraphAssertions.matches(values, in: stack)
        try await stack.writeGraph(values, batchSize: 41)
        try GraphAssertions.matches(values, in: stack)
        let reopened = try CoreDataTestStack(sqliteURL: store.url)
        try await reopened.load()
        try GraphAssertions.matches(values, in: reopened)
    }

    @Test("Parallel contexts keep resources from all five root tables")
    func separateContextsPreserveSharedResources() async throws {
        let store = try TemporarySQLiteStore()
        defer { store.remove() }
        let stack = try CoreDataTestStack(sqliteURL: store.url)
        try await stack.load()
        try await stack.importer.write([Int64(1), 2, 3]) { ids, storage in
            let resources = try storage.upsert(ids: ids, identifiedBy: Resource.identity)
            for id in ids { resources[id]?.label = "resource-\(id)" }
        }
        let values = GraphCases.roots(perKind: 80)
        let importers = (0..<5).map { _ in
            CoreDataImporter(context: stack.container.newBackgroundContext())
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for kind in RootKind.allCases {
                let groupValues = values.filter { $0.kind == kind }
                let importer = importers[kind.rawValue]
                group.addTask {
                    try await importer.write(groupValues, batchSize: 20) { batch, storage in
                        try GraphWriter.write(batch, using: storage)
                    }
                }
            }
            try await group.waitForAll()
        }
        try GraphAssertions.matches(values, in: stack)
    }

    @Test("Parallel edits change memberships and owned rows without touching other roots")
    func separateContextsReconcileIndependentRoots() async throws {
        let store = try TemporarySQLiteStore()
        defer { store.remove() }
        let stack = try CoreDataTestStack(sqliteURL: store.url)
        try await stack.load()
        let initial = GraphCases.roots(perKind: 2)
        try await stack.writeGraph(initial)

        let resourceIDsByKind: [[Int64]] = [[2, 3], [1, 3], [2], [3, 1], []]
        let edits = RootKind.allCases.map { kind in
            RootSnapshot(
                kind: kind, id: 1, title: "edited-\(kind)",
                resourceIDs: resourceIDsByKind[kind.rawValue],
                sections: [SectionSnapshot(
                    id: 2, title: "edited-section-\(kind)",
                    entries: [EntrySnapshot(position: 2, text: "edited-entry-\(kind)")]
                )]
            )
        }
        let importers = (0..<5).map { _ in
            CoreDataImporter(context: stack.container.newBackgroundContext())
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for kind in RootKind.allCases {
                let edit = edits[kind.rawValue]
                let importer = importers[kind.rawValue]
                group.addTask {
                    try await importer.write([edit]) { batch, storage in
                        try GraphWriter.write(batch, using: storage)
                    }
                }
            }
            try await group.waitForAll()
        }
        let expected = initial.filter { $0.id == 2 } + edits
        try GraphAssertions.matches(expected, in: stack)
        let reopened = try CoreDataTestStack(sqliteURL: store.url)
        try await reopened.load()
        try GraphAssertions.matches(expected, in: reopened)
    }
}
