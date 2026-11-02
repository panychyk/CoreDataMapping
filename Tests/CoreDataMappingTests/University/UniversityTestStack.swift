import CoreDataMapping

typealias UniversityTestStack = TestStack

extension TestStack {
    func write(_ graph: UniversityGraph, batchSize: Int = 500) async throws {
        try await importer.write([graph], batchSize: batchSize) { batch, storage in
            try UniversityGraphWriter.write(batch, using: storage)
        }
    }
}
