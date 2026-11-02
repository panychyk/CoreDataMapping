import CoreData
import CoreDataMapping

enum TravelGraphError: Error, Equatable {
    case missingReference(entity: String, id: Int64)
    case invalidBooking(tripID: Int64, bookingID: Int64)
    case duplicateSeat(tripID: Int64, bookingID: Int64, seat: String)
}

enum TravelGraphWriter {
    // Prepare every global identity before connecting relationships. Only trip,
    // booking, guest, payment, and ticket snapshots own child membership.
    static func write(_ graphs: [TravelGraph], using storage: CoreDataStorage) throws {
        let loyalty = try storage.upsert(
            ids: graphs.flatMap { $0.loyalty.map(\.id) }, identifiedBy: TravelLoyalty.identity)
        let travelers = try storage.upsert(
            ids: graphs.flatMap { $0.travelers.map(\.id) }, identifiedBy: TravelTraveler.identity)
        let airports = try storage.upsert(
            ids: graphs.flatMap { $0.airports.map(\.id) }, identifiedBy: TravelAirport.identity)
        let flights = try storage.upsert(
            ids: graphs.flatMap { $0.flights.map(\.id) }, identifiedBy: TravelFlight.identity)
        let hotels = try storage.upsert(
            ids: graphs.flatMap { $0.hotels.map(\.id) }, identifiedBy: TravelHotel.identity)
        let rooms = try storage.upsert(
            ids: graphs.flatMap { $0.rooms.map(\.id) }, identifiedBy: TravelRoom.identity)
        let trips = try storage.upsert(
            ids: graphs.flatMap { $0.trips.map(\.id) }, identifiedBy: TravelTrip.identity,
            prefetching: ["bookings", "bookings.guests", "bookings.payments", "bookings.tickets"])

        for graph in graphs {
            for value in graph.loyalty {
                try required(loyalty, value.id, "TravelLoyalty").name = value.name
            }
            for value in graph.travelers {
                let traveler = try required(travelers, value.id, "TravelTraveler")
                traveler.name = value.name
                traveler.loyalty = try value.loyaltyID.map { try required(loyalty, $0, "TravelLoyalty") }
            }
            for value in graph.airports {
                try required(airports, value.id, "TravelAirport").code = value.name
            }
            for value in graph.flights {
                let flight = try required(flights, value.id, "TravelFlight")
                flight.code = value.code
                flight.origin = try required(airports, value.originID, "TravelAirport")
                flight.destination = try required(airports, value.destinationID, "TravelAirport")
            }
            for value in graph.hotels {
                try required(hotels, value.id, "TravelHotel").name = value.name
            }
            for value in graph.rooms {
                let room = try required(rooms, value.id, "TravelRoom")
                room.number = value.number
                room.hotel = try required(hotels, value.hotelID, "TravelHotel")
            }
            for value in graph.trips {
                let trip = try required(trips, value.id, "TravelTrip")
                trip.title = value.title
                trip.traveler = try required(travelers, value.travelerID, "TravelTraveler")
                let bookings = try storage.reconcileOwned(
                    value.bookings,
                    current: try CoreDataStorage.ordered(trip.bookings, as: TravelBooking.self),
                    dtoId: \TravelBookingValue.localID, entityId: \TravelBooking.localID,
                    create: { try storage.insert(TravelBooking.self) }
                ) { booking, snapshot in
                    try write(snapshot, tripID: value.id, to: booking,
                              travelers: travelers, flights: flights, rooms: rooms, using: storage)
                }
                trip.bookings = try storage.replace(with: bookings)
            }
        }
    }

    private static func write(
        _ value: TravelBookingValue, tripID: Int64, to booking: TravelBooking,
        travelers: [Int64: TravelTraveler], flights: [Int64: TravelFlight],
        rooms: [Int64: TravelRoom], using storage: CoreDataStorage
    ) throws {
        guard (value.flightID == nil) != (value.roomID == nil),
              value.flightID != nil || value.tickets.isEmpty else {
            throw TravelGraphError.invalidBooking(tripID: tripID, bookingID: value.localID)
        }
        booking.localID = value.localID
        booking.status = value.status
        booking.kind = value.flightID == nil ? "hotel" : "flight"
        booking.flight = try value.flightID.map { try required(flights, $0, "TravelFlight") }
        booking.room = try value.roomID.map { try required(rooms, $0, "TravelRoom") }

        let guests = try storage.reconcileOwned(
            value.guests,
            current: try CoreDataStorage.ordered(booking.guests, as: TravelGuest.self),
            dtoId: \TravelGuestValue.localID, entityId: \TravelGuest.localID,
            create: { try storage.insert(TravelGuest.self) }
        ) { guest, snapshot in
            guest.localID = snapshot.localID
            guest.name = snapshot.name
            guest.traveler = try snapshot.travelerID.map {
                try required(travelers, $0, "TravelTraveler")
            }
        }
        booking.guests = try storage.replace(with: guests)
        let guestsByID = Dictionary(uniqueKeysWithValues: guests.map { ($0.localID, $0) })

        let payments = try storage.reconcileOwned(
            value.payments,
            current: try CoreDataStorage.ordered(booking.payments, as: TravelPayment.self),
            dtoId: \TravelPaymentValue.localID, entityId: \TravelPayment.localID,
            create: { try storage.insert(TravelPayment.self) }
        ) { payment, snapshot in
            payment.localID = snapshot.localID
            payment.amount = snapshot.amount
            payment.status = snapshot.status
        }
        booking.payments = try storage.replace(with: payments)

        var seats: Set<String> = []
        for ticket in value.tickets {
            guard seats.insert(ticket.seat).inserted else {
                throw TravelGraphError.duplicateSeat(
                    tripID: tripID, bookingID: value.localID, seat: ticket.seat)
            }
        }
        let tickets = try storage.reconcileOwned(
            value.tickets,
            current: try CoreDataStorage.ordered(booking.tickets, as: TravelTicket.self),
            dtoId: \TravelTicketValue.localID, entityId: \TravelTicket.localID,
            create: { try storage.insert(TravelTicket.self) }
        ) { ticket, snapshot in
            ticket.localID = snapshot.localID
            ticket.seat = snapshot.seat
            ticket.guest = try required(guestsByID, snapshot.guestID, "TravelGuest")
        }
        booking.tickets = try storage.replace(with: tickets)
    }

    private static func required<Value>(
        _ values: [Int64: Value], _ id: Int64, _ entity: String
    ) throws -> Value {
        guard let value = values[id] else {
            throw TravelGraphError.missingReference(entity: entity, id: id)
        }
        return value
    }
}
