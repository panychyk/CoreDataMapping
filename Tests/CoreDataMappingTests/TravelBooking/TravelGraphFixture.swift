struct TravelGraph: Sendable {
    var loyalty: [TravelNamed]
    var travelers: [TravelTravelerValue]
    var airports: [TravelNamed]
    var flights: [TravelFlightValue]
    var hotels: [TravelNamed]
    var rooms: [TravelRoomValue]
    var trips: [TravelTripValue]
}

struct TravelNamed: Sendable { var id: Int64; var name: String }
struct TravelTravelerValue: Sendable {
    var id: Int64; var name: String; var loyaltyID: Int64?
}
struct TravelFlightValue: Sendable {
    var id: Int64; var code: String; var originID: Int64; var destinationID: Int64
}
struct TravelRoomValue: Sendable {
    var id: Int64; var number: String; var hotelID: Int64
}
struct TravelTripValue: Sendable {
    var id: Int64; var title: String; var travelerID: Int64; var bookings: [TravelBookingValue]
}
struct TravelBookingValue: Sendable {
    var localID: Int64
    var status: String
    var flightID: Int64?
    var roomID: Int64?
    var guests: [TravelGuestValue]
    var payments: [TravelPaymentValue]
    var tickets: [TravelTicketValue]
}
struct TravelGuestValue: Sendable {
    var localID: Int64; var name: String; var travelerID: Int64?
}
struct TravelPaymentValue: Sendable {
    var localID: Int64; var amount: Int64; var status: String
}
struct TravelTicketValue: Sendable {
    var localID: Int64; var guestID: Int64; var seat: String
}

enum TravelGraphFixture {
    static func journey() -> TravelGraph {
        .init(
            loyalty: [.init(id: 1, name: "Sky Club"), .init(id: 2, name: "Hotel Rewards")],
            travelers: [
                .init(id: 10, name: "Ada", loyaltyID: 1),
                .init(id: 11, name: "Bohdan", loyaltyID: 1),
                .init(id: 12, name: "Clara", loyaltyID: 2),
            ],
            airports: [.init(id: 20, name: "ZAG"), .init(id: 21, name: "LHR"), .init(id: 22, name: "JFK")],
            flights: [
                .init(id: 30, code: "BA849", originID: 20, destinationID: 21),
                .init(id: 31, code: "BA117", originID: 21, destinationID: 22),
            ],
            hotels: [.init(id: 40, name: "London House"), .init(id: 41, name: "New York Plaza")],
            rooms: [.init(id: 50, number: "101", hotelID: 40), .init(id: 51, number: "202", hotelID: 41)],
            trips: [
                .init(id: 100, title: "London conference", travelerID: 10, bookings: [
                    .init(localID: 1, status: "confirmed", flightID: 30, roomID: nil,
                          guests: [.init(localID: 1, name: "Ada", travelerID: 10),
                                   .init(localID: 2, name: "Bohdan", travelerID: 11)],
                          payments: [.init(localID: 1, amount: 400, status: "captured"),
                                     .init(localID: 2, amount: 50, status: "pending")],
                          tickets: [.init(localID: 1, guestID: 1, seat: "12A"),
                                    .init(localID: 2, guestID: 2, seat: "12B")]),
                    .init(localID: 2, status: "confirmed", flightID: nil, roomID: 50,
                          guests: [.init(localID: 1, name: "Ada", travelerID: 10),
                                   .init(localID: 2, name: "Bohdan", travelerID: 11)],
                          payments: [.init(localID: 1, amount: 300, status: "captured")], tickets: []),
                ]),
                .init(id: 101, title: "London weekend", travelerID: 11, bookings: [
                    .init(localID: 1, status: "confirmed", flightID: 30, roomID: nil,
                          guests: [.init(localID: 1, name: "Bohdan", travelerID: 11)],
                          payments: [.init(localID: 1, amount: 200, status: "captured")],
                          tickets: [.init(localID: 1, guestID: 1, seat: "14C")]),
                    .init(localID: 2, status: "held", flightID: nil, roomID: 50,
                          guests: [.init(localID: 1, name: "Bohdan", travelerID: 11)],
                          payments: [], tickets: []),
                ]),
                .init(id: 102, title: "New York holiday", travelerID: 12, bookings: [
                    .init(localID: 1, status: "confirmed", flightID: 31, roomID: nil,
                          guests: [.init(localID: 1, name: "Clara", travelerID: 12)],
                          payments: [.init(localID: 1, amount: 800, status: "captured")],
                          tickets: [.init(localID: 1, guestID: 1, seat: "3A")]),
                    .init(localID: 2, status: "confirmed", flightID: nil, roomID: 51,
                          guests: [.init(localID: 1, name: "Clara", travelerID: 12)],
                          payments: [.init(localID: 1, amount: 700, status: "captured")], tickets: []),
                ]),
            ]
        )
    }
}
