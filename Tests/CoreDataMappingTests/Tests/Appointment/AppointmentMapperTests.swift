import Foundation
import Testing

@Suite("Appointment mappers")
struct AppointmentMapperTests {

    @Test("Maps an appointment DTO to its domain summary")
    func mapsAppointmentSummary() {
        let dto = TestDTOFactory.appointment(
            topics: [
                ReservationTopicDTO(ReservationTopicID: 801, Name: "Product"),
                ReservationTopicDTO(ReservationTopicID: 802, Name: nil)
            ],
            customFields: [
                CustomFieldDTO(
                    CustomFieldID: 1,
                    FieldValue: "Medium",
                    FieldMultipleValues: []
                ),
                CustomFieldDTO(
                    CustomFieldID: 2,
                    FieldValue: nil,
                    FieldMultipleValues: [
                        CustomFieldValueDTO(
                            FieldValue: "Project Cedar",
                            FieldValueEntityID: 90_020,
                            FieldValueEntityType: .CompanyCustomer
                        )
                    ]
                )
            ]
        )

        let summary = AppointmentSummaryMapper().map(dto)

        #expect(
            summary == AppointmentSummary(
                id: 200_001,
                startDate: Date(timeIntervalSince1970: 1_767_254_400),
                endDate: Date(timeIntervalSince1970: 1_767_257_100),
                name: "Customer Discovery",
                isDraft: false,
                status: .confirmed,
                topics: [
                    ReservationTopic(id: 801, name: "Product"),
                    ReservationTopic(id: 802, name: nil)
                ],
                realLocation: RealLocation(
                    id: "location-2",
                    name: "Split Conference Center",
                    address: "Obala kneza Branimira 17",
                    latitude: 43.5081,
                    longitude: 16.4402
                ),
                customFields: [
                    CustomField(id: 1, value: "Medium", multipleValues: []),
                    CustomField(
                        id: 2,
                        value: nil,
                        multipleValues: [
                            CustomFieldValue(
                                value: "Project Cedar",
                                entityId: 90_020,
                                entityType: .companyCustomer
                            )
                        ]
                    )
                ]
            )
        )
    }

    @Test("Maps every appointment status")
    func mapsStatuses() {
        #expect(AppointmentStatusMapper.map(.Pending) == .pending)
        #expect(AppointmentStatusMapper.map(.Confirmed) == .confirmed)
        #expect(AppointmentStatusMapper.map(.Declined) == .declined)
        #expect(AppointmentStatusMapper.map(.Cancelled) == .cancelled)
        #expect(AppointmentStatusMapper.map(.Planned) == .planned)
    }
}
