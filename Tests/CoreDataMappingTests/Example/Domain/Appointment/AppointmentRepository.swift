import Foundation

nonisolated protocol AppointmentRepository: Sendable {
    func getAppointmentsList(for seminarId: Int) async throws -> [AppointmentSummary]
}
