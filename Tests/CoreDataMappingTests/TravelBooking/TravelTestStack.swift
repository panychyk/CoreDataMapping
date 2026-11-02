import CoreDataMapping

typealias TravelTestStack = TestStack

extension TestStack {
    func write(_ graph: TravelGraph, batchSize: Int = 500) async throws {
        try await importer.write([graph], batchSize: batchSize) { batch, storage in
            try TravelGraphWriter.write(batch, using: storage)
        }
    }

    func writeTrips(_ graph: TravelGraph, batchSize: Int) async throws {
        let pages = graph.trips.map { trip -> TravelGraph in
            var page = graph
            page.trips = [trip]
            return page
        }
        try await importer.write(pages, batchSize: batchSize) { batch, storage in
            try TravelGraphWriter.write(batch, using: storage)
        }
    }
}
