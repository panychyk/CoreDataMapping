struct CongressGraph: Sendable {
    var congress: CongressValue
    var organizations: [OrganizationValue]
    var people: [PersonValue]
    var venue: VenueValue
    var rooms: [RoomValue]
    var resources: [ResourceValue]
    var events: [EventValue]
}

struct CongressValue: Sendable {
    var id: Int64
    var title: String
}
struct OrganizationValue: Sendable {
    var id: Int64
    var name: String
}
struct PersonValue: Sendable {
    var id: Int64
    var name: String
    var organizationID: Int64
}
struct VenueValue: Sendable {
    var id: Int64
    var name: String
}
struct RoomValue: Sendable {
    var id: Int64
    var name: String
}
struct ResourceValue: Sendable {
    var id: Int64
    var title: String
}

struct EventValue: Sendable {
    var id: Int64
    var title: String
    var tracks: [TrackValue]
    var appointments: [AppointmentValue]
    var registrations: [RegistrationValue]
    var sponsorIDs: [Int64]
}

struct TrackValue: Sendable {
    var id: Int64
    var title: String
    var sessions: [SessionValue]
}
struct SessionValue: Sendable {
    var id: Int64
    var title: String
    var roomID: Int64
    var speakerIDs: [Int64]
    var resourceIDs: [Int64]
}
struct AppointmentValue: Sendable {
    var id: Int64
    var title: String
    var roomID: Int64
    var participants: [ParticipantValue]
}
struct ParticipantValue: Sendable {
    var personID: Int64
    var status: String
}
struct RegistrationValue: Sendable {
    var personID: Int64
    var status: String
    var checkInIDs: [Int64]
}

/// Builds the shared input graph for the MedicalCongress storage tests.
/// Each call returns fresh values that a test can change for its own scenario.
/// The graph reuses people, rooms, and resources across two events so tests can
/// check both shared relationships and parent-owned children.
enum CongressGraphFixture {
    static func congress() -> CongressGraph {
        CongressGraph(
            congress: .init(id: 100, title: "European Oncology Congress"),
            organizations: [
                .init(id: 1, name: "City Hospital"),
                .init(id: 2, name: "Nova Therapeutics"),
            ],
            people: [
                .init(id: 10, name: "Dr. Olena Kovalenko", organizationID: 1),
                .init(id: 11, name: "Dr. Marko Horvat", organizationID: 1),
                .init(id: 12, name: "Iryna Novak", organizationID: 2),
            ],
            venue: .init(id: 20, name: "Congress Center"),
            rooms: [.init(id: 21, name: "Hall A"), .init(id: 22, name: "Meeting Room B")],
            resources: [
                .init(id: 30, title: "Oncology overview"),
                .init(id: 31, title: "Clinical results"),
            ],
            events: [
                .init(
                    id: 40, title: "Research Day",
                    tracks: [
                        .init(
                            id: 1, title: "Research",
                            sessions: [
                                .init(
                                    id: 1, title: "New therapies", roomID: 21,
                                    speakerIDs: [10, 11], resourceIDs: [30, 31])
                            ])
                    ],
                    appointments: [
                        .init(
                            id: 1, title: "Advisory meeting", roomID: 22,
                            participants: [
                                .init(personID: 10, status: "confirmed"),
                                .init(personID: 12, status: "confirmed"),
                            ]),
                        .init(
                            id: 2, title: "Follow-up", roomID: 22,
                            participants: [.init(personID: 10, status: "invited")]),
                    ],
                    registrations: [
                        .init(personID: 10, status: "registered", checkInIDs: [1]),
                        .init(personID: 11, status: "registered", checkInIDs: []),
                    ],
                    sponsorIDs: [2]
                ),
                .init(
                    id: 41, title: "Clinical Roundtable",
                    tracks: [
                        .init(
                            id: 1, title: "Practice",
                            sessions: [
                                .init(
                                    id: 1, title: "Treatment pathways", roomID: 21,
                                    speakerIDs: [10], resourceIDs: [30])
                            ])
                    ],
                    appointments: [
                        .init(
                            id: 1, title: "Expert exchange", roomID: 22,
                            participants: [.init(personID: 10, status: "confirmed")])
                    ],
                    registrations: [
                        .init(personID: 10, status: "registered", checkInIDs: []),
                        .init(personID: 12, status: "registered", checkInIDs: []),
                    ],
                    sponsorIDs: [2]
                ),
            ]
        )
    }
}
