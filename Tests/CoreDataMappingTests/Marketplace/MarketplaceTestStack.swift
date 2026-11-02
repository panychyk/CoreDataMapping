import CoreDataMapping

typealias MarketplaceTestStack = TestStack

extension TestStack {
    func write(_ graph: MarketplaceGraph, batchSize: Int = 500) async throws {
        try await importer.write([graph], batchSize: batchSize) { batch, storage in
            try MarketplaceGraphWriter.write(batch, using: storage)
        }
    }
}
