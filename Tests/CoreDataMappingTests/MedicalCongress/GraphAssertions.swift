import CoreData
import CoreDataMapping
import Testing

@MainActor
enum GraphAssertions {
    static func matches(_ graph: CongressGraph, in stack: CongressTestStack) throws {
        stack.resetViewContext()
        try matchesSharedEntities(graph, in: stack)
        try matchesEvents(graph, in: stack)
        try matchesOwnedChildren(graph, in: stack)
        try auditIdentitiesAndRelationships(in: stack)
    }

    private static func matchesSharedEntities(
        _ graph: CongressGraph, in stack: CongressTestStack
    ) throws {
        let congresses = try stack.fetch(Congress.self)
        let organizations = try stack.fetch(Organization.self)
        let people = try stack.fetch(Person.self)
        let venues = try stack.fetch(Venue.self)
        let rooms = try stack.fetch(Room.self)
        let resources = try stack.fetch(ResourceAsset.self)

        #expect(congresses.count == 1)
        #expect(congresses.first?.id == graph.congress.id)
        #expect(congresses.first?.title == graph.congress.title)
        #expect(organizations.count == graph.organizations.count)
        #expect(people.count == graph.people.count)
        #expect(venues.count == 1)
        #expect(rooms.count == graph.rooms.count)
        #expect(resources.count == graph.resources.count)

        #expect(Set(organizations.map(\.id)) == Set(graph.organizations.map(\.id)))
        #expect(Set(people.map(\.id)) == Set(graph.people.map(\.id)))
        #expect(Set(rooms.map(\.id)) == Set(graph.rooms.map(\.id)))
        #expect(Set(resources.map(\.id)) == Set(graph.resources.map(\.id)))
        #expect(venues.first?.id == graph.venue.id)
        #expect(venues.first?.name == graph.venue.name)

        for organization in graph.organizations {
            #expect(organizations.first { $0.id == organization.id }?.name == organization.name)
        }

        for person in graph.people {
            let stored = try #require(people.first { $0.id == person.id })
            #expect(stored.name == person.name)
            #expect(stored.organization?.id == person.organizationID)
        }
        for room in rooms {
            #expect(room.venue?.id == graph.venue.id)
            #expect(room.name == graph.rooms.first { $0.id == room.id }?.name)
        }
        for resource in graph.resources {
            #expect(resources.first { $0.id == resource.id }?.title == resource.title)
        }
    }

    private static func matchesEvents(
        _ graph: CongressGraph, in stack: CongressTestStack
    ) throws {
        let events = try stack.fetch(CongressEvent.self)
        #expect(events.count == graph.events.count)
        #expect(Set(events.map(\.id)) == Set(graph.events.map(\.id)))

        for snapshot in graph.events {
            let event = try #require(events.first { $0.id == snapshot.id })
            #expect(event.title == snapshot.title)
            #expect(event.congress?.id == graph.congress.id)
            #expect(event.venue?.id == graph.venue.id)
            let tracks = try CoreDataStorage.ordered(event.tracks, as: Track.self)
            #expect(tracks.map(\.localID) == snapshot.tracks.map(\.id))
            for (track, wanted) in zip(tracks, snapshot.tracks) {
                #expect(track.title == wanted.title)
                let sessions = try CoreDataStorage.ordered(track.sessions, as: Session.self)
                #expect(sessions.map(\.localID) == wanted.sessions.map(\.id))
                for (session, details) in zip(sessions, wanted.sessions) {
                    #expect(session.title == details.title)
                    #expect(session.room?.id == details.roomID)
                    let speakers = session.speakers?.allObjects as? [SessionSpeaker] ?? []
                    #expect(speakers.count == details.speakerIDs.count)
                    #expect(Set(speakers.map(\.localID)) == Set(details.speakerIDs))
                    for speaker in speakers {
                        #expect(speaker.person?.id == speaker.localID)
                    }
                    #expect(
                        ids(session.resources as? Set<ResourceAsset>, \.id)
                            == Set(details.resourceIDs))
                }
            }
            let appointments = try CoreDataStorage.ordered(event.appointments, as: Appointment.self)
            #expect(appointments.map(\.localID) == snapshot.appointments.map(\.id))
            for (appointment, wanted) in zip(appointments, snapshot.appointments) {
                #expect(appointment.title == wanted.title)
                #expect(appointment.room?.id == wanted.roomID)
                let participants =
                    appointment.participants?.allObjects as? [AppointmentParticipant] ?? []
                #expect(participants.count == wanted.participants.count)
                #expect(
                    Set(participants.map(\.localID)) == Set(wanted.participants.map(\.personID)))
                for participant in participants {
                    let expected = wanted.participants.first { $0.personID == participant.localID }
                    #expect(participant.status == expected?.status)
                    #expect(participant.person?.id == participant.localID)
                }
            }
            let registrations = event.registrations?.allObjects as? [Registration] ?? []
            #expect(registrations.count == snapshot.registrations.count)
            #expect(
                Set(registrations.map(\.localID)) == Set(snapshot.registrations.map(\.personID)))
            for registration in registrations {
                let expected = try #require(
                    snapshot.registrations.first { $0.personID == registration.localID })
                #expect(registration.person?.id == expected.personID)
                #expect(registration.status == expected.status)
                let checkIns = registration.checkIns?.allObjects as? [CheckIn] ?? []
                #expect(checkIns.count == expected.checkInIDs.count)
                #expect(Set(checkIns.map(\.localID)) == Set(expected.checkInIDs))
            }
            let sponsors = event.sponsors?.allObjects as? [EventSponsor] ?? []
            #expect(sponsors.count == snapshot.sponsorIDs.count)
            #expect(Set(sponsors.map(\.localID)) == Set(snapshot.sponsorIDs))
            for sponsor in sponsors {
                #expect(sponsor.organization?.id == sponsor.localID)
            }
        }
    }

    private static func matchesOwnedChildren(
        _ graph: CongressGraph, in stack: CongressTestStack
    ) throws {
        #expect(try stack.count(Track.self) == graph.events.reduce(0) { $0 + $1.tracks.count })
        #expect(
            try stack.count(Session.self)
                == graph.events.reduce(0) { $0 + $1.tracks.reduce(0) { $0 + $1.sessions.count } })
        #expect(
            try stack.count(Appointment.self)
                == graph.events.reduce(0) { $0 + $1.appointments.count })
        #expect(
            try stack.count(AppointmentParticipant.self)
                == graph.events.reduce(0) {
                    $0 + $1.appointments.reduce(0) { $0 + $1.participants.count }
                })
        #expect(
            try stack.count(Registration.self)
                == graph.events.reduce(0) { $0 + $1.registrations.count })
        #expect(
            try stack.count(CheckIn.self)
                == graph.events.reduce(0) {
                    $0 + $1.registrations.reduce(0) { $0 + $1.checkInIDs.count }
                })
        #expect(
            try stack.count(EventSponsor.self)
                == graph.events.reduce(0) { $0 + $1.sponsorIDs.count })
        #expect(
            try stack.count(SessionSpeaker.self)
                == graph.events.reduce(0) {
                    $0
                        + $1.tracks.reduce(0) {
                            $0 + $1.sessions.reduce(0) { $0 + $1.speakerIDs.count }
                        }
                })
        #expect(try stack.fetch(Track.self).allSatisfy { $0.event != nil })
        #expect(try stack.fetch(Session.self).allSatisfy { $0.track != nil })
        #expect(try stack.fetch(Appointment.self).allSatisfy { $0.event != nil && $0.room != nil })
        #expect(
            try stack.fetch(AppointmentParticipant.self).allSatisfy {
                $0.appointment != nil && $0.person != nil
            })
        #expect(
            try stack.fetch(Registration.self).allSatisfy { $0.event != nil && $0.person != nil })
        #expect(try stack.fetch(CheckIn.self).allSatisfy { $0.registration != nil })
        #expect(
            try stack.fetch(EventSponsor.self).allSatisfy {
                $0.event != nil && $0.organization != nil
            })
        #expect(
            try stack.fetch(SessionSpeaker.self).allSatisfy {
                $0.session != nil && $0.person != nil
            })
    }

    private static func ids<Entity: NSManagedObject>(
        _ values: Set<Entity>?, _ keyPath: KeyPath<Entity, Int64>
    ) -> Set<Int64> {
        Set((values ?? []).map { $0[keyPath: keyPath] })
    }

    private struct OwnedKey: Hashable {
        let owner: NSManagedObjectID
        let localID: Int64
    }

    private static func auditIdentitiesAndRelationships(in stack: CongressTestStack) throws {
        let congresses = try stack.fetch(Congress.self)
        let organizations = try stack.fetch(Organization.self)
        let people = try stack.fetch(Person.self)
        let venues = try stack.fetch(Venue.self)
        let rooms = try stack.fetch(Room.self)
        let resources = try stack.fetch(ResourceAsset.self)
        let events = try stack.fetch(CongressEvent.self)
        let tracks = try stack.fetch(Track.self)
        let sessions = try stack.fetch(Session.self)
        let speakers = try stack.fetch(SessionSpeaker.self)
        let appointments = try stack.fetch(Appointment.self)
        let participants = try stack.fetch(AppointmentParticipant.self)
        let registrations = try stack.fetch(Registration.self)
        let checkIns = try stack.fetch(CheckIn.self)
        let sponsors = try stack.fetch(EventSponsor.self)

        uniqueGlobal(congresses, id: \.id)
        uniqueGlobal(organizations, id: \.id)
        uniqueGlobal(people, id: \.id)
        uniqueGlobal(venues, id: \.id)
        uniqueGlobal(rooms, id: \.id)
        uniqueGlobal(resources, id: \.id)
        uniqueGlobal(events, id: \.id)

        uniqueOwned(tracks, owner: \.event, id: \.localID)
        uniqueOwned(sessions, owner: \.track, id: \.localID)
        uniqueOwned(speakers, owner: \.session, id: \.localID)
        uniqueOwned(appointments, owner: \.event, id: \.localID)
        uniqueOwned(participants, owner: \.appointment, id: \.localID)
        uniqueOwned(registrations, owner: \.event, id: \.localID)
        uniqueOwned(checkIns, owner: \.registration, id: \.localID)
        uniqueOwned(sponsors, owner: \.event, id: \.localID)

        for congress in congresses {
            #expect(relationshipIDs(congress.events) == objectIDs(events.filter {
                $0.congress === congress
            }))
        }
        for venue in venues {
            #expect(relationshipIDs(venue.rooms) == objectIDs(rooms.filter {
                $0.venue === venue
            }))
            #expect(relationshipIDs(venue.events) == objectIDs(events.filter {
                $0.venue === venue
            }))
        }
        for organization in organizations {
            #expect(relationshipIDs(organization.people) == objectIDs(people.filter {
                $0.organization === organization
            }))
            #expect(relationshipIDs(organization.sponsorships) == objectIDs(sponsors.filter {
                $0.organization === organization
            }))
        }
        for person in people {
            #expect(relationshipIDs(person.speakingRoles) == objectIDs(speakers.filter {
                $0.person === person
            }))
            #expect(relationshipIDs(person.appointments) == objectIDs(participants.filter {
                $0.person === person
            }))
            #expect(relationshipIDs(person.registrations) == objectIDs(registrations.filter {
                $0.person === person
            }))
        }
        for room in rooms {
            #expect(relationshipIDs(room.sessions) == objectIDs(sessions.filter {
                $0.room === room
            }))
            #expect(relationshipIDs(room.appointments) == objectIDs(appointments.filter {
                $0.room === room
            }))
        }
        for resource in resources {
            #expect(relationshipIDs(resource.sessions) == objectIDs(sessions.filter {
                relationshipIDs($0.resources).contains(resource.objectID)
            }))
        }
    }

    private static func uniqueGlobal<Entity: NSManagedObject>(
        _ values: [Entity], id: KeyPath<Entity, Int64>
    ) {
        #expect(Set(values.map { $0[keyPath: id] }).count == values.count)
    }

    private static func uniqueOwned<Entity: NSManagedObject, Owner: NSManagedObject>(
        _ values: [Entity], owner: KeyPath<Entity, Owner?>, id: KeyPath<Entity, Int64>
    ) {
        let keys = values.compactMap { value -> OwnedKey? in
            guard let parent = value[keyPath: owner] else { return nil }
            return OwnedKey(owner: parent.objectID, localID: value[keyPath: id])
        }
        #expect(keys.count == values.count)
        #expect(Set(keys).count == keys.count)
    }

    private static func objectIDs<Entity: NSManagedObject>(
        _ values: [Entity]
    ) -> Set<NSManagedObjectID> {
        Set(values.map(\.objectID))
    }

    private static func relationshipIDs(_ values: NSSet?) -> Set<NSManagedObjectID> {
        Set((values?.allObjects ?? []).compactMap { ($0 as? NSManagedObject)?.objectID })
    }
}
