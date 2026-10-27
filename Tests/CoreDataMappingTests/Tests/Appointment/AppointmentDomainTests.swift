import Foundation
import Testing

@Suite("Appointment domain model")
struct AppointmentDomainTests {

    @Test("Exposes identity and value equality")
    func appointmentSummaryValueSemantics() {
        let summary = AppointmentSummary(
            id: 200_001,
            startDate: nil,
            endDate: nil,
            name: "Customer Discovery",
            isDraft: true,
            status: .planned,

        )
        let copy = AppointmentSummary(
            id: 200_001,
            startDate: nil,
            endDate: nil,
            name: "Customer Discovery",
            isDraft: true,
            status: .planned
        )

        #expect(summary.id == 200_001)
        #expect(summary.startDate == nil)
        #expect(summary.endDate == nil)
        #expect(summary == copy)
    }

    @Test("Appointment statuses are distinct domain values")
    func appointmentStatusesAreDistinct() {
        let statuses: [AppointmentStatus] = [
            .pending,
            .confirmed,
            .declined,
            .cancelled,
            .planned
        ]

        #expect(Set(statuses.map(String.init(describing:))).count == 5)
    }
}
