import CoreData
import CoreDataMapping
import Testing

@MainActor
@Suite("Graph model relationships")
struct GraphSchemaTests {
    @Test("The model defines inverse and delete rules for all five roots")
    func modelDefinesInverseOrderingAndDeleteRules() throws {
        let url = try #require(Bundle.module.url(forResource: "GraphModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        for entity in model.entities {
            for relation in entity.relationshipsByName.values {
                #expect(relation.inverseRelationship?.inverseRelationship === relation)
            }
        }
        for name in ["Document", "Folder", "Dashboard", "Board", "Workspace"] {
            let root = try #require(model.entitiesByName[name])
            #expect(root.relationshipsByName["sections"]?.deleteRule == .cascadeDeleteRule)
            #expect(root.relationshipsByName["sections"]?.isOrdered == true)
        }
        #expect(model.entitiesByName["Document"]?.relationshipsByName["resources"]?.isOrdered == true)
        #expect(model.entitiesByName["Folder"]?.relationshipsByName["resources"]?.isOrdered == false)
        #expect(model.entitiesByName["Dashboard"]?.relationshipsByName["featuredResource"]?.isToMany == false)
    }

}
