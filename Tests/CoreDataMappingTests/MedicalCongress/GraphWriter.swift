import CoreData
import CoreDataMapping

enum GraphFixtureError: Error, Equatable {
    case missingReference(entity: String, id: Int64)
}

enum GraphWriter {
    // Relationship rule: global people, rooms and resources are shared. Only
    // tracks, sessions, appointments, registrations and join rows are owned.
    // Prepare all global identities before connecting the graph.
    static func write(_ graphs: [CongressGraph], using storage: CoreDataStorage) throws {
        let congresses = try storage.upsert(
            ids: graphs.map(\.congress.id), identifiedBy: Congress.identity
        )
        let organizations = try storage.upsert(
            ids: graphs.flatMap { $0.organizations.map(\.id) },
            identifiedBy: Organization.identity
        )
        let people = try storage.upsert(
            ids: graphs.flatMap { $0.people.map(\.id) }, identifiedBy: Person.identity
        )
        let venues = try storage.upsert(
            ids: graphs.map(\.venue.id), identifiedBy: Venue.identity
        )
        let rooms = try storage.upsert(
            ids: graphs.flatMap { $0.rooms.map(\.id) }, identifiedBy: Room.identity
        )
        let resources = try storage.upsert(
            ids: graphs.flatMap { $0.resources.map(\.id) },
            identifiedBy: ResourceAsset.identity
        )
        let events = try storage.upsert(
            ids: graphs.flatMap { $0.events.map(\.id) },
            identifiedBy: CongressEvent.identity,
            prefetching: [
                "tracks.sessions", "tracks.sessions.speakers", "appointments.participants",
                "registrations.checkIns", "sponsors",
            ]
        )

        for graph in graphs {
            let congress = try required(congresses, id: graph.congress.id, entity: "Congress")
            congress.title = graph.congress.title
            let venue = try required(venues, id: graph.venue.id, entity: "Venue")
            venue.name = graph.venue.name
            for value in graph.organizations {
                try required(organizations, id: value.id, entity: "Organization").name = value.name
            }
            for value in graph.people {
                let person = try required(people, id: value.id, entity: "Person")
                person.name = value.name
                person.organization = try required(
                    organizations, id: value.organizationID, entity: "Organization")
            }
            for value in graph.rooms {
                let room = try required(rooms, id: value.id, entity: "Room")
                room.name = value.name
                room.venue = venue
            }
            for value in graph.resources {
                try required(resources, id: value.id, entity: "ResourceAsset").title = value.title
            }
            for value in graph.events {
                let event = try required(events, id: value.id, entity: "CongressEvent")
                event.title = value.title
                event.congress = congress
                event.venue = venue
                try write(
                    value, to: event, people: people, rooms: rooms,
                    resources: resources, organizations: organizations, using: storage)
            }
        }
    }

    private static func write(
        _ value: EventValue,
        to event: CongressEvent,
        people: [Int64: Person],
        rooms: [Int64: Room],
        resources: [Int64: ResourceAsset],
        organizations: [Int64: Organization],
        using storage: CoreDataStorage
    ) throws {
        let tracks = try storage.reconcileOwned(
            value.tracks, current: try CoreDataStorage.ordered(event.tracks, as: Track.self),
            dtoId: \TrackValue.id, entityId: \Track.localID,
            create: { try storage.insert(Track.self) }
        ) { track, snapshot in
            track.localID = snapshot.id
            track.title = snapshot.title
            let sessions = try storage.reconcileOwned(
                snapshot.sessions,
                current: try CoreDataStorage.ordered(track.sessions, as: Session.self),
                dtoId: \SessionValue.id, entityId: \Session.localID,
                create: { try storage.insert(Session.self) }
            ) { session, details in
                session.localID = details.id
                session.title = details.title
                session.room = try required(rooms, id: details.roomID, entity: "Room")
                session.resources = NSSet(
                    array: Array(
                        try storage.replaceUnordered(
                            with: try details.resourceIDs.map {
                                try required(resources, id: $0, entity: "ResourceAsset")
                            }
                        )))
                let speakers = try storage.reconcileOwned(
                    details.speakerIDs,
                    current: try objects(session.speakers),
                    dtoId: \.self, entityId: \SessionSpeaker.localID,
                    create: { try storage.insert(SessionSpeaker.self) }
                ) { speaker, personID in
                    speaker.localID = personID
                    speaker.person = try required(people, id: personID, entity: "Person")
                }
                session.speakers = NSSet(array: speakers)
            }
            track.sessions = try storage.replace(with: sessions)
        }
        event.tracks = try storage.replace(with: tracks)

        let appointments = try storage.reconcileOwned(
            value.appointments,
            current: try CoreDataStorage.ordered(event.appointments, as: Appointment.self),
            dtoId: \AppointmentValue.id, entityId: \Appointment.localID,
            create: { try storage.insert(Appointment.self) }
        ) { appointment, snapshot in
            appointment.localID = snapshot.id
            appointment.title = snapshot.title
            appointment.room = try required(rooms, id: snapshot.roomID, entity: "Room")
            let participants = try storage.reconcileOwned(
                snapshot.participants, current: try objects(appointment.participants),
                dtoId: \ParticipantValue.personID,
                entityId: \AppointmentParticipant.localID,
                create: { try storage.insert(AppointmentParticipant.self) }
            ) { participant, details in
                participant.localID = details.personID
                participant.status = details.status
                participant.person = try required(people, id: details.personID, entity: "Person")
            }
            appointment.participants = NSSet(array: participants)
        }
        event.appointments = try storage.replace(with: appointments)

        let registrations = try storage.reconcileOwned(
            value.registrations, current: try objects(event.registrations),
            dtoId: \RegistrationValue.personID, entityId: \Registration.localID,
            create: { try storage.insert(Registration.self) }
        ) { registration, snapshot in
            registration.localID = snapshot.personID
            registration.status = snapshot.status
            registration.person = try required(people, id: snapshot.personID, entity: "Person")
            let checkIns = try storage.reconcileOwned(
                snapshot.checkInIDs, current: try objects(registration.checkIns),
                dtoId: \.self, entityId: \CheckIn.localID,
                create: { try storage.insert(CheckIn.self) }
            ) { checkIn, identifier in
                checkIn.localID = identifier
            }
            registration.checkIns = NSSet(array: checkIns)
        }
        event.registrations = NSSet(array: registrations)

        let sponsors = try storage.reconcileOwned(
            value.sponsorIDs, current: try objects(event.sponsors),
            dtoId: \.self, entityId: \EventSponsor.localID,
            create: { try storage.insert(EventSponsor.self) }
        ) { sponsorship, organizationID in
            sponsorship.localID = organizationID
            sponsorship.organization = try required(
                organizations, id: organizationID, entity: "Organization")
        }
        event.sponsors = NSSet(array: sponsors)
    }

    private static func objects<Entity: NSManagedObject>(_ set: NSSet?) throws -> [Entity] {
        guard let set else { return [] }
        guard let values = set.allObjects as? [Entity] else {
            throw CoreDataStorageError.unexpectedRelationshipEntityType(
                expectedType: String(describing: Entity.self))
        }
        return values
    }

    private static func required<Value>(
        _ values: [Int64: Value], id: Int64, entity: String
    ) throws -> Value {
        guard let value = values[id] else {
            throw GraphFixtureError.missingReference(entity: entity, id: id)
        }
        return value
    }
}
