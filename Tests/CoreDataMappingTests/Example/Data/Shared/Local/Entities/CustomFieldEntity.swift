import CoreData

@objc(CustomFieldEntity)
nonisolated final class CustomFieldEntity: NSManagedObject {
    @NSManaged var id: Int
    @NSManaged var value: String?
    @NSManaged var appointment: AppointmentEntity?
    @NSManaged var scheduleEvent: ScheduleEventEntity?
    @NSManaged var elective: ElectiveEntity?
    @NSManaged var multipleValues: Set<CustomFieldValueEntity>?
}
