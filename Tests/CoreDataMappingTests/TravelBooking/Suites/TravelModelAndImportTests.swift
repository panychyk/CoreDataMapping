import CoreData
import CoreDataMapping
import Testing

/// Verifies the schema and initial travel graph import. Cascade applies only
/// to trip and booking children; the catalog remains shared.
///
/// - `schemaRules`: inverses, delete rules, and identity constraints match ownership.
/// - `fullGraph`: three trips with repeated local IDs preserve every link.
/// - `sharedCatalog`: multiple bookings reuse the same flight and room.
@MainActor
@Suite("Travel · model and initial import")
struct TravelModelAndImportTests {
    @Test("Travel schema separates owned rows from shared catalog")
    func schemaRules() throws {
        let url = try #require(Bundle.module.url(forResource: "TestModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        #expect(model.entities.count == 49)
        for name in ["TravelTraveler", "TravelTrip", "TravelFlight", "TravelAirport",
                     "TravelHotel", "TravelRoom", "TravelLoyalty"] {
            let entity = try #require(model.entitiesByName[name])
            #expect(entity.uniquenessConstraints.count == 1)
        }
        for name in ["TravelBooking", "TravelGuest", "TravelPayment", "TravelTicket"] {
            let entity = try #require(model.entitiesByName[name])
            #expect(entity.uniquenessConstraints.isEmpty)
        }
        for (entityName, relationshipName) in [
            ("TravelTrip", "bookings"), ("TravelBooking", "guests"),
            ("TravelBooking", "payments"), ("TravelBooking", "tickets"),
        ] {
            let relationship = try #require(model.entitiesByName[entityName]?.relationshipsByName[relationshipName])
            #expect(relationship.deleteRule == .cascadeDeleteRule)
            #expect(relationship.isOrdered)
        }
        for (entityName, relationshipName) in [
            ("TravelFlight", "bookings"), ("TravelRoom", "bookings"),
            ("TravelHotel", "rooms"), ("TravelTraveler", "trips"),
            ("TravelLoyalty", "travelers"), ("TravelGuest", "tickets"),
        ] {
            let relationship = try #require(model.entitiesByName[entityName]?.relationshipsByName[relationshipName])
            #expect(relationship.deleteRule == .nullifyDeleteRule)
        }
        for name in ["TravelTraveler", "TravelTrip", "TravelBooking", "TravelFlight",
                     "TravelAirport", "TravelHotel", "TravelRoom", "TravelGuest",
                     "TravelPayment", "TravelTicket", "TravelLoyalty"] {
            let entity = try #require(model.entitiesByName[name])
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship?.inverseRelationship === relationship)
            }
        }
    }

    @Test("Full graph keeps tickets and payments inside their own bookings")
    func fullGraph() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let graph = TravelGraphFixture.journey()
        try await stack.write(graph)
        try TravelGraphAssertions.matches(graph, in: stack)
    }

    @Test("One flight and one hotel room serve bookings from different travelers")
    func sharedCatalog() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        try await stack.write(TravelGraphFixture.journey())
        stack.resetViewContext()
        let flight = try #require(stack.fetch(TravelFlight.self).first { $0.id == 30 })
        let room = try #require(stack.fetch(TravelRoom.self).first { $0.id == 50 })
        let flightBookings = try #require(flight.bookings?.allObjects as? [TravelBooking])
        let roomBookings = try #require(room.bookings?.allObjects as? [TravelBooking])
        #expect(Set(flightBookings.compactMap(\.trip?.id)) == [100, 101])
        #expect(Set(roomBookings.compactMap(\.trip?.id)) == [100, 101])
        let airport = try #require(stack.fetch(TravelAirport.self).first { $0.id == 21 })
        #expect(airport.arrivals?.count == 1)
        #expect(airport.departures?.count == 1)
    }
}
