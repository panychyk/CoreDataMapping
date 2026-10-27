import Foundation
import Testing

@Suite("Appointment DTO")
struct AppointmentDTOTests {

    @Test("Decodes the appointments response envelope")
    func decodesResponseEnvelope() throws {
        let json = Data(#"{"Items":[]}"#.utf8)

        let response = try APIJSONDecoder.make().decode(
            AppointmentsResponseDTO.self,
            from: json
        )

        #expect(response.Items.isEmpty)
    }

    @Test("Decodes an appointment's real location")
    func decodesRealLocation() throws {
        let json = Data(
            """
            {
              "RealLocationID": "location-2",
              "Name": "Split Conference Center",
              "Address": "Obala kneza Branimira 17",
              "Lat": 43.5081,
              "Lng": 16.4402
            }
            """.utf8
        )

        let location = try APIJSONDecoder.make().decode(
            RealLocationDTO.self,
            from: json
        )

        #expect(location.RealLocationID == "location-2")
        #expect(location.Name == "Split Conference Center")
        #expect(location.Lat == 43.5081)
        #expect(location.Lng == 16.4402)
    }

    @Test("Decodes one complete appointment contract with nested relationships")
    func decodesAppointmentGraph() throws {
        let json = Data(
            """
            {"Items":[{
              "CreatorUserID":10,"RoomIDs":[101],"RoomReservationUserID":201,
              "IsDraft":false,"AppointmentName":"Planning","SeminarID":3001,
              "StartDateUTC":"2026-01-01T10:00:00Z",
              "Status":"Confirmed","Priority":"Tier2",
              "MetadataDictionaryItems":[],"User":{"UserID":10},
              "Topics":[{"ReservationTopicID":7,"Name":"Roadmap"}],
              "RealLocation":{"RealLocationID":"loc-1","Lat":43.5,"Lng":16.4},
              "DisableSendInvitations":false,"DisableSendUpdates":false,
              "AskCustomer":false,"RegistrationEnabled":true,
              "TeleconferenceType":"Disabled","UserTeams":[],
              "FormatType":"InPerson","ResourceEnabled":false,
              "PartnerType":"Master","SegmentsCount":1,
              "CustomFields":[{"CustomFieldID":4,"FieldValue":"A","FieldMultipleValues":[]}]
            }]}
            """.utf8
        )
        let response = try APIJSONDecoder.make().decode(
            AppointmentsResponseDTO.self, from: json
        )
        let appointment = try #require(response.Items.first)
        #expect(appointment.RoomReservationUserID == 201)
        #expect(appointment.User.UserID == 10)
        #expect(appointment.Topics?.map(\.ReservationTopicID) == [7])
        #expect(appointment.CustomFields?.map(\.CustomFieldID) == [4])
        #expect(appointment.StartDateUTC != nil)
    }
}
