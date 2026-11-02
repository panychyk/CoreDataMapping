import CoreData
import CoreDataMapping
import Testing

/// Перевіряє правила моделі та перший запис повного університетського графа.
/// Проведення курсу володіє дітьми, а викладачі й аудиторії є спільними.
///
/// - `schemaRules`: усі 12 Entity мають inverse; owned-зв’язки каскадні.
/// - `fullGraph`: курс у двох семестрах і студент у трьох проведеннях зберігають правильні оцінки.
@MainActor
@Suite("University · model and initial import")
struct UniversityModelAndImportTests {
    @Test("University model encodes scoped ownership and shared references")
    func schemaRules() throws {
        let url = try #require(Bundle.module.url(forResource: "TestModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        #expect(model.entities.count == 49)
        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship?.inverseRelationship === relationship)
            }
        }
        for (entityName, relationshipName) in [
            ("UniOffering", "assignments"), ("UniOffering", "enrollments"),
            ("UniEnrollment", "grades"),
        ] {
            let entity = try #require(model.entitiesByName[entityName])
            #expect(entity.relationshipsByName[relationshipName]?.deleteRule == .cascadeDeleteRule)
        }
        for (entityName, relationshipName) in [
            ("UniTeacher", "offerings"), ("UniRoom", "offerings"),
            ("UniCourse", "offerings"), ("UniStudent", "enrollments"),
            ("UniAssignment", "grades"),
        ] {
            let entity = try #require(model.entitiesByName[entityName])
            #expect(entity.relationshipsByName[relationshipName]?.deleteRule == .nullifyDeleteRule)
        }
        for name in ["UniFaculty", "UniProgram", "UniGroup", "UniStudent",
                     "UniTeacher", "UniRoom", "UniCourse", "UniSemester", "UniOffering"] {
            let entity = try #require(model.entitiesByName[name])
            #expect(entity.uniquenessConstraints.count == 1)
        }
        for name in ["UniEnrollment", "UniAssignment", "UniGrade"] {
            let entity = try #require(model.entitiesByName[name])
            #expect(entity.uniquenessConstraints.isEmpty)
        }
    }

    @Test("Full graph keeps grades in their own course offering")
    func fullGraph() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let graph = UniversityGraphFixture.university()
        try await stack.write(graph)
        try UniversityGraphAssertions.matches(graph, in: stack)
        let algorithms = try #require(stack.fetch(UniCourse.self).first { $0.id == 60 })
        #expect(Set((algorithms.offerings?.allObjects as? [UniOffering] ?? []).map(\.semester?.id)) == [70, 71])
        let ada = try #require(stack.fetch(UniStudent.self).first { $0.id == 30 })
        #expect(Set((ada.enrollments?.allObjects as? [UniEnrollment] ?? []).compactMap(\.offering?.id)) == [100, 101, 102])
        let teacher = try #require(stack.fetch(UniTeacher.self).first { $0.id == 40 })
        #expect(teacher.offerings?.count == 2)
        let room = try #require(stack.fetch(UniRoom.self).first { $0.id == 50 })
        #expect(room.offerings?.count == 2)
    }
}
