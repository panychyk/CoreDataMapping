import CoreDataMapping
import Testing

@MainActor
@Suite("Medical congress · read rollback")
struct ReadRollbackTests {
    @Test("Mutation during read fails without saving")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        await #expect(throws: CoreDataImportError.mutationDuringRead) {
            try await stack.importer.read([Int64(30)]) { ids, storage in
                _ = try storage.upsert(ids: ids, identifiedBy: ResourceAsset.identity)
                return [Int64]()
            }
        }
        #expect(try stack.count(ResourceAsset.self) == 0)
    }
}
