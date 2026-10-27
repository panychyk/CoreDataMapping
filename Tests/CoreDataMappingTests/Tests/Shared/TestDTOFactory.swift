import Foundation

nonisolated enum TestDTOFactory {
    static let defaultStartDate = Date(timeIntervalSince1970: 1_767_254_400)
    static let defaultEndDate = Date(timeIntervalSince1970: 1_767_257_100)
    static let defaultRealLocation = RealLocationDTO(
        RealLocationID: "location-2",
        Name: "Split Conference Center",
        Address: "Obala kneza Branimira 17",
        Lat: 43.5081,
        Lng: 16.4402
    )

    static func appointment(
        id: Int = 200_001,
        seminarId: Int = 3_001,
        name: String = "Customer Discovery",
        startDate: Date? = defaultStartDate,
        endDate: Date? = defaultEndDate,
        isDraft: Bool = false,
        status: RoomReservationUserStatus = .Confirmed,
        seminarOpportunities: [SeminarOpportunityDTO]? = [],
        attendees: [AttendeeDTO]? = [],
        topics: [ReservationTopicDTO]? = [],
        realLocation: RealLocationDTO = defaultRealLocation,
        user: UserDTO = defaultUser(),
        customFields: [CustomFieldDTO]? = []
    ) -> AppointmentDTO {
        AppointmentDTO(
            SeminarOpportunities: seminarOpportunities,
            Attendees: attendees,
            CreatorUserID: 10_001,
            RoomIDs: [101],
            RoomNameOnRental: nil,
            RoomReservationUserID: id,
            IsDraft: isDraft,
            AppointmentName: name,
            StartDate: startDate?.addingTimeInterval(3_600),
            EndDate: endDate?.addingTimeInterval(3_600),
            StartDateUTC: startDate,
            EndDateUTC: endDate,
            SeminarID: seminarId,
            SeminarTimeZoneID: "Europe/Zagreb",
            SpecialInstructions: nil,
            DurationInMinutes: 45,
            Status: status,
            Priority: .Tier2,
            MetadataDictionaryItems: [],
            User: user,
            Topics: topics,
            CustomRoomName: nil,
            RealLocation: realLocation,
            DisableSendInvitations: false,
            DisableSendUpdates: false,
            ReservationUrl: nil,
            AskCustomer: false,
            RegistrationEnabled: true,
            TeleconferenceUrl: nil,
            TeleconferenceDetails: nil,
            TeleconferenceType: .Disabled,
            StartedSeminarPresentationUniqueID: nil,
            RoomReservationImageUrl: nil,
            RoomReservationImageTabletUrl: nil,
            UserTeams: [],
            FormatType: .InPerson,
            ResourceEnabled: false,
            PartnerType: .Master,
            SegmentsCount: 1,
            CustomFields: customFields
        )
    }

    static func defaultUser(id: Int = 10_001) -> UserDTO {
        UserDTO(
            UserID: id,
            Prefix: nil,
            FirstName: "Marko",
            LastName: "Marić",
            Email: "marko@example.test",
            IconPath: nil,
            Position: nil,
            Company: "Northstar",
            FullName: "Marko Marić"
        )
    }

    static func attendee(userId: Int) -> AttendeeDTO {
        AttendeeDTO(
            UserID: userId,
            Status: .Accepted,
            StatusUpdatedDateUTC: defaultStartDate,
            ParticipationStatus: .Participated,
            StateID: 12,
            CountryID: 34,
            IsCustomer: true,
            Duplicate: false,
            DraftSelectDateEmailOpened: nil,
            InvitationEmailOpened: defaultEndDate
        )
    }

    /// A repeatable graph with shared dependencies and two levels of owned children.
    static func richAppointment(id: Int) -> AppointmentDTO {
        appointment(
            id: id,
            seminarOpportunities: [SeminarOpportunityDTO(
                SeminarOpportunityID: 70, Ordinal: 1, Name: "Shared opportunity"
            )],
            attendees: [attendee(userId: 10_001), attendee(userId: 20_001)],
            topics: [1, 2, 3].map {
                ReservationTopicDTO(ReservationTopicID: $0, Name: "Topic \($0)")
            },
            customFields: [1, 2].map { fieldId in
                CustomFieldDTO(
                    CustomFieldID: fieldId,
                    FieldValue: "Field \(fieldId)",
                    FieldMultipleValues: [1, 2, 3].map { valueId in
                        CustomFieldValueDTO(
                            FieldValue: "Root \(id), field \(fieldId), value \(valueId)",
                            FieldValueEntityID: id * 100 + fieldId * 10 + valueId,
                            FieldValueEntityType: .CompanyCustomer
                        )
                    }
                )
            }
        )
    }
}
