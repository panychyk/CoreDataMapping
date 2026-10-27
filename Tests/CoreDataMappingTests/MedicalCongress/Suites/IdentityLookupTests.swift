import CoreDataMapping
import Testing

@MainActor
@Suite("Medical congress · identity lookup")
struct IdentityLookupTests {
    @Test("Batch lookup deduplicates global IDs and omits missing IDs")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        try await stack.importer.write([Int64(30), 31, 30], batchSize: 2) { ids, storage in
            let resources = try storage.upsert(
                ids: ids, identifiedBy: ResourceAsset.identity, fetchChunkSize: 1
            )
            for id in ids { resources[id]?.title = "Resource \(id)" }
        }
        let found = try await stack.importer.read([Int64(31), 30, 99]) { ids, storage in
            let resources = try storage.existing(
                ids: ids, identifiedBy: ResourceAsset.identity, fetchChunkSize: 1
            )
            return ids.compactMap { resources[$0]?.id }
        }
        #expect(found == [31, 30])
        #expect(try stack.count(ResourceAsset.self) == 2)
        await #expect(throws: CoreDataStorageError.invalidFetchChunkSize(0)) {
            try await stack.importer.read([Int64(30)]) { ids, storage in
                _ = try storage.existing(
                    ids: ids, identifiedBy: ResourceAsset.identity, fetchChunkSize: 0
                )
                return [Int64]()
            }
        }
    }
}
