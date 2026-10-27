import CoreData
import Testing

@Suite("Example relationship schema")
struct RelationshipSchemaTests {
    @Test("Every relationship has a matching inverse")
    func allRelationshipsHaveInverses() throws {
        let model = try model()
        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                let inverse = try #require(relationship.inverseRelationship)
                #expect(inverse.inverseRelationship === relationship)
                #expect(inverse.destinationEntity === entity)
            }
        }
    }

    @Test("Owned children cascade; shared rows nullify; ordered lists stay ordered")
    func ownershipAndOrderAreExplicit() throws {
        let model = try model()
        try expectRelationship(model, "AppointmentEntity", "attendees", .cascadeDeleteRule)
        try expectRelationship(model, "AppointmentEntity", "customFields", .cascadeDeleteRule, ordered: true)
        try expectRelationship(model, "AppointmentEntity", "topics", .nullifyDeleteRule, ordered: true)
        try expectRelationship(model, "AppointmentEntity", "realLocation", .nullifyDeleteRule)
        try expectRelationship(model, "ScheduleEventEntity", "reservation", .cascadeDeleteRule)
        try expectRelationship(model, "ElectiveEntity", "tracks", .nullifyDeleteRule, ordered: true)
        try expectRelationship(model, "CustomFieldEntity", "multipleValues", .cascadeDeleteRule)
    }

    private func model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.module.url(
            forResource: "PersistenceModel", withExtension: "momd"
        ))
        return try #require(NSManagedObjectModel(contentsOf: url))
    }

    private func expectRelationship(
        _ model: NSManagedObjectModel,
        _ entityName: String,
        _ relationshipName: String,
        _ deleteRule: NSDeleteRule,
        ordered: Bool = false
    ) throws {
        let entity = try #require(model.entitiesByName[entityName])
        let relationship = try #require(entity.relationshipsByName[relationshipName])
        #expect(relationship.deleteRule == deleteRule)
        #expect(relationship.isOrdered == ordered)
    }
}
