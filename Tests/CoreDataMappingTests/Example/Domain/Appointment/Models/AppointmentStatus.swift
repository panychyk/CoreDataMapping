import Foundation

nonisolated enum AppointmentStatus: String, Sendable, Equatable {
    case pending
    case confirmed
    case declined
    case cancelled
    case planned
}
