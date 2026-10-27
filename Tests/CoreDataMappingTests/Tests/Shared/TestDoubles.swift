
nonisolated enum APIClientStubError: Error, Equatable {
    case expected
    case unexpectedRequest(APIRequest)
    case unexpectedResponseType(String)
}

nonisolated struct APIClientStub: APIClient {
    let expectedRequest: APIRequest
    private let result: Result<any Sendable, APIClientStubError>

    init(expectedRequest: APIRequest, response: any Sendable) {
        self.expectedRequest = expectedRequest
        result = .success(response)
    }

    init(expectedRequest: APIRequest, error: APIClientStubError) {
        self.expectedRequest = expectedRequest
        result = .failure(error)
    }

    func get<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        request: APIRequest
    ) async throws -> Response {
        guard request == expectedRequest else {
            throw APIClientStubError.unexpectedRequest(request)
        }
        let response = try result.get()
        guard let response = response as? Response else {
            throw APIClientStubError.unexpectedResponseType(
                String(describing: responseType)
            )
        }
        return response
    }
}
