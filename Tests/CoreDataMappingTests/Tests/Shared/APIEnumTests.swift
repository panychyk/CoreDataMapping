import Foundation
import Testing

@Suite("API enums")
struct APIEnumTests {

    @Test("Decodes string raw values")
    func decodesRawValues() throws {
        let decoder = JSONDecoder()

        #expect(try decoder.decode(EventType.self, from: Data(#""RoomReservation""#.utf8)) == .RoomReservation)
        #expect(try decoder.decode(HomeSectionType.self, from: Data(#""TileVideo""#.utf8)) == .TileVideo)
        #expect(try decoder.decode(TeleconferenceEntityType.self, from: Data(#""MSTeams""#.utf8)) == .MSTeams)
        #expect(try decoder.decode(RoomReservationUserStatus.self, from: Data(#""Confirmed""#.utf8)) == .Confirmed)
        #expect(try decoder.decode(UserAttendType.self, from: Data(#""InPerson""#.utf8)) == .InPerson)
    }
}
