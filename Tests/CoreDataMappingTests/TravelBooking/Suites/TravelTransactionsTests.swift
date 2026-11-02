import CoreDataMapping
import Testing

/// Перевіряє відкат складного вкладеного snapshot і межі batch.
/// Помилка не залишає частково змінених дітей або спільних посилань.
///
/// - `duplicateChildRollback`: повторний ID платежу відкочує цілий імпорт.
/// - `foreignGuestRollback`: квиток на гостя поза бронюванням відхиляється.
/// - `invalidKindRollback`: бронювання з рейсом і номером одночасно відхиляється.
/// - `duplicateSeatRollback`: повторне місце у квитках того самого бронювання відкочується.
/// - `laterBatchRollback`: збережений перший batch лишається після помилки другого.
@MainActor
@Suite("Travel · import transactions")
struct TravelTransactionsTests {
    @Test("Duplicate scoped payment ID rolls back edited booking and catalog")
    func duplicateChildRollback() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let original = TravelGraphFixture.journey()
        try await stack.write(original)
        var broken = original
        broken.flights[0].code = "CHANGED"
        broken.trips[0].bookings[0].status = "changed"
        broken.trips[0].bookings[0].payments.append(
            .init(localID: 1, amount: 999, status: "captured"))
        await #expect(throws: CoreDataStorageError.self) {
            try await stack.write(broken)
        }
        try TravelGraphAssertions.matches(original, in: stack)
    }

    @Test("A ticket cannot refer to a guest outside its own booking")
    func foreignGuestRollback() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let original = TravelGraphFixture.journey()
        try await stack.write(original)
        var broken = original
        broken.trips[0].bookings[0].tickets[0].guestID = 3
        broken.trips[0].bookings[0].payments[0].amount = 1
        await #expect(throws: TravelGraphError.missingReference(entity: "TravelGuest", id: 3)) {
            try await stack.write(broken)
        }
        try TravelGraphAssertions.matches(original, in: stack)
    }

    @Test("A booking cannot simultaneously point at a flight and a room")
    func invalidKindRollback() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let original = TravelGraphFixture.journey()
        try await stack.write(original)
        var broken = original
        broken.trips[0].bookings[0].roomID = 50
        await #expect(throws: TravelGraphError.invalidBooking(tripID: 100, bookingID: 1)) {
            try await stack.write(broken)
        }
        try TravelGraphAssertions.matches(original, in: stack)
    }

    @Test("Duplicate ticket seat rolls back all changes in the booking")
    func duplicateSeatRollback() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        let original = TravelGraphFixture.journey()
        try await stack.write(original)
        var broken = original
        broken.trips[0].bookings[0].tickets[1].seat = "12A"
        broken.trips[0].bookings[0].payments[0].amount = 1
        await #expect(throws: TravelGraphError.duplicateSeat(
            tripID: 100, bookingID: 1, seat: "12A")) {
            try await stack.write(broken)
        }
        try TravelGraphAssertions.matches(original, in: stack)
    }

    @Test("A failed later batch keeps the earlier trip committed")
    func laterBatchRollback() async throws {
        let stack = try TravelTestStack()
        try await stack.load()
        var incoming = TravelGraphFixture.journey()
        incoming.trips[1].bookings[0].tickets[0].guestID = 99
        await #expect(throws: TravelGraphError.missingReference(entity: "TravelGuest", id: 99)) {
            try await stack.writeTrips(incoming, batchSize: 1)
        }
        var expected = TravelGraphFixture.journey()
        expected.trips = [expected.trips[0]]
        try TravelGraphAssertions.matches(expected, in: stack)
    }
}
