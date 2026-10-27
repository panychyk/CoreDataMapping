import Foundation
import Testing

@Suite("Small API contract samples")
struct ProgramContractTests {
    @Test("Decodes track, schedule, and elective envelopes with shared references")
    func decodesProgramEnvelopes() throws {
        let decoder = APIJSONDecoder.make()
        let tracks = try decoder.decode(TracksResponseDTO.self, from: Data(
            #"{"ReturnValue":{"Items":[{"SeminarTrackID":7,"Name":"Blue"}]}}"#.utf8
        ))
        let schedule = try decoder.decode(ScheduleResponseDTO.self, from: Data(
            #"{"ReturnValue":{"Events":[{"Event":{"UniqueID":11,"EventID":12,"SeminarVersionID":13,"EntityEventType":"Event","Ordinal":1,"Tracks":[{"SeminarTrackID":7}]}}],"Reservations":[]}}"#.utf8
        ))
        let electives = try decoder.decode(ElectivesResponseDTO.self, from: Data(
            #"{"ReturnValue":{"Items":[{"EventID":21,"Ordinal":1,"Tracks":[{"SeminarTrackID":7}]}]}}"#.utf8
        ))

        #expect(tracks.ReturnValue.Items.map(\.SeminarTrackID) == [7])
        #expect(schedule.ReturnValue.Events.first?.Event.Tracks?.map(\.SeminarTrackID) == [7])
        #expect(electives.ReturnValue.Items.first?.Tracks?.map(\.SeminarTrackID) == [7])
    }
}
