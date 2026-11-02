import CoreData
import CoreDataMapping
import Testing

@MainActor
enum TravelGraphAssertions {
    static func trip(_ id: Int64, in stack: TravelTestStack) throws -> TravelTrip {
        try #require(stack.fetch(TravelTrip.self).first { $0.id == id })
    }

    static func booking(_ localID: Int64, tripID: Int64, in stack: TravelTestStack) throws -> TravelBooking {
        let trip = try trip(tripID, in: stack)
        return try #require(CoreDataStorage.ordered(trip.bookings, as: TravelBooking.self)
            .first { $0.localID == localID })
    }

    static func matches(_ graph: TravelGraph, in stack: TravelTestStack) throws {
        stack.resetViewContext()
        let travelers = try stack.fetch(TravelTraveler.self)
        let loyalty = try stack.fetch(TravelLoyalty.self)
        let airports = try stack.fetch(TravelAirport.self)
        let flights = try stack.fetch(TravelFlight.self)
        let hotels = try stack.fetch(TravelHotel.self)
        let rooms = try stack.fetch(TravelRoom.self)
        let trips = try stack.fetch(TravelTrip.self)
        #expect(travelers.count == graph.travelers.count)
        #expect(loyalty.count == graph.loyalty.count)
        #expect(airports.count == graph.airports.count)
        #expect(flights.count == graph.flights.count)
        #expect(hotels.count == graph.hotels.count)
        #expect(rooms.count == graph.rooms.count)
        #expect(trips.count == graph.trips.count)
        for value in graph.loyalty {
            #expect(loyalty.first { $0.id == value.id }?.name == value.name)
        }
        for value in graph.travelers {
            let traveler = try #require(travelers.first { $0.id == value.id })
            #expect(traveler.name == value.name)
            #expect(traveler.loyalty?.id == value.loyaltyID)
        }
        for value in graph.airports {
            #expect(airports.first { $0.id == value.id }?.code == value.name)
        }
        for value in graph.flights {
            let flight = try #require(flights.first { $0.id == value.id })
            #expect(flight.code == value.code)
            #expect(flight.origin?.id == value.originID)
            #expect(flight.destination?.id == value.destinationID)
        }
        for value in graph.hotels {
            #expect(hotels.first { $0.id == value.id }?.name == value.name)
        }
        for value in graph.rooms {
            let room = try #require(rooms.first { $0.id == value.id })
            #expect(room.number == value.number)
            #expect(room.hotel?.id == value.hotelID)
        }
        for value in graph.trips {
            let trip = try #require(trips.first { $0.id == value.id })
            #expect(trip.title == value.title)
            #expect(trip.traveler?.id == value.travelerID)
            let bookings = try CoreDataStorage.ordered(trip.bookings, as: TravelBooking.self)
            #expect(bookings.map(\.localID) == value.bookings.map(\.localID))
            for (booking, snapshot) in zip(bookings, value.bookings) {
                #expect(booking.trip === trip)
                #expect(booking.status == snapshot.status)
                #expect(booking.kind == (snapshot.flightID == nil ? "hotel" : "flight"))
                #expect(booking.flight?.id == snapshot.flightID)
                #expect(booking.room?.id == snapshot.roomID)
                let guests = try CoreDataStorage.ordered(booking.guests, as: TravelGuest.self)
                #expect(guests.map(\.localID) == snapshot.guests.map(\.localID))
                for (guest, wanted) in zip(guests, snapshot.guests) {
                    #expect(guest.booking === booking)
                    #expect(guest.name == wanted.name)
                    #expect(guest.traveler?.id == wanted.travelerID)
                }
                let payments = try CoreDataStorage.ordered(booking.payments, as: TravelPayment.self)
                #expect(payments.map(\.localID) == snapshot.payments.map(\.localID))
                for (payment, wanted) in zip(payments, snapshot.payments) {
                    #expect(payment.booking === booking)
                    #expect(payment.amount == wanted.amount)
                    #expect(payment.status == wanted.status)
                }
                let tickets = try CoreDataStorage.ordered(booking.tickets, as: TravelTicket.self)
                #expect(tickets.map(\.localID) == snapshot.tickets.map(\.localID))
                for (ticket, wanted) in zip(tickets, snapshot.tickets) {
                    #expect(ticket.booking === booking)
                    #expect(ticket.seat == wanted.seat)
                    #expect(ticket.guest?.localID == wanted.guestID)
                    #expect(ticket.guest?.booking === booking)
                }
            }
        }
        let snapshots = graph.trips.flatMap(\.bookings)
        #expect(try stack.count(TravelBooking.self) == snapshots.count)
        #expect(try stack.count(TravelGuest.self) == snapshots.reduce(0) { $0 + $1.guests.count })
        #expect(try stack.count(TravelPayment.self) == snapshots.reduce(0) { $0 + $1.payments.count })
        #expect(try stack.count(TravelTicket.self) == snapshots.reduce(0) { $0 + $1.tickets.count })
    }
}
