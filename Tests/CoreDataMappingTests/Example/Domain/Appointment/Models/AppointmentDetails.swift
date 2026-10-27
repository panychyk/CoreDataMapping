nonisolated struct ReservationTopic: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String?
}

nonisolated struct RealLocation: Sendable, Equatable {
    let id: String
    let name: String?
    let address: String?
    let latitude: Double
    let longitude: Double
}
