import CoreData
import CoreDataMapping
import Testing

/// Перевіряє повторний імпорт, зміну маршруту й каскадне видалення.
/// Локальні ID із різних бронювань не зливаються, а спільний каталог зберігається.
///
/// - `sequentialTrips`: окремі batch збирають один спільний каталог.
/// - `repeatPreservesIdentity`: повторний snapshot не створює нових дітей.
/// - `rebookAndReconcile`: зміна рейсу, гостей, платежів і квитків локальна.
/// - `sharedCatalogUpdate`: зміна аеропорту, готелю й лояльності відбивається на всіх посиланнях.
/// - `cancelStay`: вилучення бронювання видаляє лише його дітей.
/// - `deleteTrip`: видалення root каскадно видаляє бронювання без втрати каталогу.
@MainActor
@Suite("Travel · history and lifecycle")
struct TravelHistoryAndLifecycleTests {
    @Test("Separate trip batches assemble shared flights and rooms")
    func sequentialTrips() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let graph = TravelGraphFixture.journey()
        try await stack.writeTrips(graph, batchSize: 1)
        try TravelGraphAssertions.matches(graph, in: stack)
    }

    @Test("Repeated graph reuses every trip, booking, guest, payment and ticket")
    func repeatPreservesIdentity() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let graph = TravelGraphFixture.journey()
        try await stack.write(graph)
        let before = try ownedIDs(in: stack)
        try await stack.write(graph)
        try TravelGraphAssertions.matches(graph, in: stack)
        #expect(try ownedIDs(in: stack) == before)
    }

    @Test("Rebooking one flight reconciles nested children and leaves other trips intact")
    func rebookAndReconcile() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        var expected = TravelGraphFixture.journey()
        try await stack.write(expected)
        let otherBefore = try TravelGraphAssertions.booking(1, tripID: 101, in: stack).objectID
        expected.trips[0].bookings[0].flightID = 31
        expected.trips[0].bookings[0].status = "rebooked"
        expected.trips[0].bookings[0].guests.removeLast()
        expected.trips[0].bookings[0].guests.append(
            .init(localID: 3, name: "Clara", travelerID: 12))
        expected.trips[0].bookings[0].payments.removeLast()
        expected.trips[0].bookings[0].payments[0].status = "refunded"
        expected.trips[0].bookings[0].payments.append(
            .init(localID: 3, amount: 950, status: "captured"))
        expected.trips[0].bookings[0].tickets[0].seat = "4A"
        expected.trips[0].bookings[0].tickets[1] =
            .init(localID: 3, guestID: 3, seat: "4B")
        var delta = expected
        delta.trips = [expected.trips[0]]
        try await stack.write(delta)
        try TravelGraphAssertions.matches(expected, in: stack)
        #expect(try TravelGraphAssertions.booking(1, tripID: 101, in: stack).objectID == otherBefore)
        let oldFlight = try #require(stack.fetch(TravelFlight.self).first { $0.id == 30 })
        #expect(oldFlight.bookings?.count == 1)
        let newFlight = try #require(stack.fetch(TravelFlight.self).first { $0.id == 31 })
        #expect(newFlight.bookings?.count == 2)
    }

    @Test("Shared airport, hotel and loyalty changes reach all linked travelers and bookings")
    func sharedCatalogUpdate() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        var expected = TravelGraphFixture.journey()
        try await stack.write(expected)
        let roomBefore = try #require(stack.fetch(TravelRoom.self).first { $0.id == 50 }).objectID
        expected.airports[1].name = "LHR Terminal 5"
        expected.hotels[0].name = "London House Renovated"
        expected.loyalty[0].name = "Sky Club Plus"
        expected.travelers[1].loyaltyID = 2
        try await stack.write(expected)
        try TravelGraphAssertions.matches(expected, in: stack)
        let room = try #require(stack.fetch(TravelRoom.self).first { $0.id == 50 })
        #expect(room.objectID == roomBefore)
        #expect(room.bookings?.count == 2)
        #expect(room.hotel?.name == "London House Renovated")
        let airport = try #require(stack.fetch(TravelAirport.self).first { $0.id == 21 })
        #expect(airport.arrivals?.count == 1)
        #expect(airport.departures?.count == 1)
        let loyalty = try #require(stack.fetch(TravelLoyalty.self).first { $0.id == 1 })
        #expect(loyalty.travelers?.count == 1)
    }

    @Test("Removing one hotel booking deletes its guests and payment only")
    func cancelStay() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        var expected = TravelGraphFixture.journey()
        try await stack.write(expected)
        expected.trips[0].bookings.remove(at: 1)
        var delta = expected
        delta.trips = [expected.trips[0]]
        try await stack.write(delta)
        try TravelGraphAssertions.matches(expected, in: stack)
        let room = try #require(stack.fetch(TravelRoom.self).first { $0.id == 50 })
        #expect(room.bookings?.count == 1)
        #expect(try TravelGraphAssertions.booking(2, tripID: 101, in: stack).room === room)
    }

    @Test("Deleting a trip cascades only its owned graph")
    func deleteTrip() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let graph = TravelGraphFixture.journey()
        try await stack.write(graph)
        let removed = try await stack.importer.transaction { context in
            let request = NSFetchRequest<TravelTrip>(entityName: "TravelTrip")
            request.predicate = NSPredicate(format: "id == %lld", 100)
            guard let trip = try context.fetch(request).first else { return false }
            context.delete(trip)
            return true
        }
        #expect(removed)
        var expected = graph
        expected.trips.removeFirst()
        try TravelGraphAssertions.matches(expected, in: stack)
        #expect(try stack.fetch(TravelFlight.self).first { $0.id == 30 }?.bookings?.count == 1)
        #expect(try stack.fetch(TravelRoom.self).first { $0.id == 50 }?.bookings?.count == 1)
    }

    private func ownedIDs(in stack: TravelTestStack) throws -> Set<NSManagedObjectID> {
        Set(try stack.fetch(TravelTrip.self).map(\.objectID)
            + stack.fetch(TravelBooking.self).map(\.objectID)
            + stack.fetch(TravelGuest.self).map(\.objectID)
            + stack.fetch(TravelPayment.self).map(\.objectID)
            + stack.fetch(TravelTicket.self).map(\.objectID))
    }
}
