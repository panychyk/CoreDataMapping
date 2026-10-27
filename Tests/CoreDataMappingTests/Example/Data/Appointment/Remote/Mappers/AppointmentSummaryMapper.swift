nonisolated protocol AppointmentSummaryMapping: Sendable {
    func map(_ dto: AppointmentDTO) -> AppointmentSummary
}

nonisolated struct AppointmentSummaryMapper: AppointmentSummaryMapping {
    func map(_ dto: AppointmentDTO) -> AppointmentSummary {
        AppointmentSummary(
            id: dto.RoomReservationUserID,
            startDate: dto.StartDateUTC,
            endDate: dto.EndDateUTC,
            name: dto.AppointmentName,
            isDraft: dto.IsDraft,
            status: AppointmentStatusMapper.map(dto.Status),
            topics: dto.Topics?.map { ReservationTopicMapper.map($0) } ?? [],
            realLocation: RealLocationMapper.map(dto.RealLocation),
            customFields: dto.CustomFields?.map { CustomFieldMapper.map($0) } ?? []
        )
    }
}
