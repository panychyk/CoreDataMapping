import CoreData
import Testing

@MainActor
@Suite("Medical congress · schema rules")
struct SchemaRulesTests {
    @Test("Every relationship has an inverse and ownership uses cascade")
    func scenario() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "MedicalCongressModel", withExtension: "momd"
            ))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        #expect(model.entities.count == 15)
        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship?.inverseRelationship === relationship)
            }
        }
        let event = try #require(model.entitiesByName["CongressEvent"])
        #expect(event.relationshipsByName["tracks"]?.deleteRule == .cascadeDeleteRule)
        #expect(event.relationshipsByName["appointments"]?.deleteRule == .cascadeDeleteRule)
        let appointment = try #require(model.entitiesByName["Appointment"])
        #expect(appointment.relationshipsByName["participants"]?.deleteRule == .cascadeDeleteRule)
        let session = try #require(model.entitiesByName["Session"])
        #expect(session.relationshipsByName["resources"]?.deleteRule == .nullifyDeleteRule)
        #expect(session.relationshipsByName["room"]?.deleteRule == .nullifyDeleteRule)
    }
}
