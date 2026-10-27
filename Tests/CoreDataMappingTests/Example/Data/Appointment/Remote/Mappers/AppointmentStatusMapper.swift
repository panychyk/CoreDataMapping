nonisolated enum AppointmentStatusMapper {
    static func map(_ status: RoomReservationUserStatus) -> AppointmentStatus {
        switch status {
            case .Pending: .pending
            case .Confirmed: .confirmed
            case .Declined: .declined
            case .Cancelled: .cancelled
            case .Planned: .planned
        }
    }
}
