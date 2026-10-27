import Foundation

nonisolated enum APIRequest: Sendable, Equatable {
    case tracks
    case schedule
    case electives
    case appointments(seminarId: Int)
}

nonisolated protocol APIClient: Sendable {
    func get<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        request: APIRequest
    ) async throws -> Response
}

/// A test-only API boundary; repositories receive deterministic response data.
nonisolated struct DefaultAPIClient: APIClient {
    typealias ResponseProvider = @Sendable (APIRequest) async throws -> Data

    private let responseProvider: ResponseProvider

    init(responseProvider: @escaping ResponseProvider) {
        self.responseProvider = responseProvider
    }

    func get<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        request: APIRequest
    ) async throws -> Response {
        let data = try await responseProvider(request)
        return try APIJSONDecoder.make().decode(responseType, from: data)
    }
}
