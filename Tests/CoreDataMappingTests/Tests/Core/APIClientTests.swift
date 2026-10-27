import Foundation
import Testing

@Suite("API client")
struct APIClientTests {

    @Test("Decodes response data supplied for the request")
    func decodesProvidedResponse() async throws {
        let client = DefaultAPIClient { request in
            #expect(request == .appointments(seminarId: 3_001))
            return Data(#"{"Items":[]}"#.utf8)
        }

        let response = try await client.get(
            AppointmentsResponseDTO.self,
            request: .appointments(seminarId: 3_001)
        )

        #expect(response.Items.isEmpty)
    }

    @Test("Uses the same client for different API requests")
    func supportsMultipleRequests() async throws {
        let client = DefaultAPIClient { request in
            switch request {
            case .tracks:
                Data(#"{"ReturnValue":{"Items":[]}}"#.utf8)
            case .schedule:
                Data(#"{"ReturnValue":{"Events":[],"Reservations":[]}}"#.utf8)
            case .electives:
                Data(#"{"ReturnValue":{"Items":[]}}"#.utf8)
            case .appointments:
                Data(#"{"Items":[]}"#.utf8)
            }
        }
        let appointments = try await client.get(
            AppointmentsResponseDTO.self,
            request: .appointments(seminarId: 3_001)
        )

        #expect(appointments.Items.isEmpty)
    }

}
