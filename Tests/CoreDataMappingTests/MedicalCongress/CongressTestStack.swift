import CoreDataMapping

typealias CongressTestStack = TestStack

extension TestStack {
    func write(_ graph: CongressGraph, batchSize: Int = 500) async throws {
        try await importer.write([graph], batchSize: batchSize) { batch, storage in
            try GraphWriter.write(batch, using: storage)
        }
    }
}
