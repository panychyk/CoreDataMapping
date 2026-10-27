nonisolated enum ReservationTopicMapper {
    static func map(_ dto: ReservationTopicDTO) -> ReservationTopic {
        ReservationTopic(
            id: dto.ReservationTopicID,
            name: dto.Name
        )
    }
}

nonisolated enum RealLocationMapper {
    static func map(_ dto: RealLocationDTO) -> RealLocation {
        RealLocation(
            id: dto.RealLocationID,
            name: dto.Name,
            address: dto.Address,
            latitude: dto.Lat,
            longitude: dto.Lng
        )
    }
}
