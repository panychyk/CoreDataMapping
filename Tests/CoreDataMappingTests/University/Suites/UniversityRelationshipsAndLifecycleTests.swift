import CoreData
import CoreDataMapping
import Testing

/// Перевіряє складні зміни зв’язків і каскадне видалення в університеті.
/// Повний snapshot узгоджує лише дітей свого проведення; shared-рядки залишаються.
///
/// - `moveSharedResources`: зміна викладача, аудиторії та групи зберігає інші проведення.
/// - `reconcileOwnedGraph`: вилучення запису й завдання прибирає їхні оцінки тільки в одному проведенні.
/// - `deleteOffering`: видалення проведення каскадно прибирає дітей, лишаючи курс, семестр і shared-рядки.
@MainActor
@Suite("University · relationships and lifecycle")
struct UniversityRelationshipsAndLifecycleTests {
    @Test("Teacher, room and student group changes preserve shared rows")
    func moveSharedResources() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        var expected = UniversityGraphFixture.university()
        try await stack.write(expected)
        expected.offerings[0].teacherID = 41
        expected.offerings[0].roomID = 51
        expected.students[0].groupID = 21
        try await stack.write(expected)
        try UniversityGraphAssertions.matches(expected, in: stack)
        let first = try UniversityGraphAssertions.offering(100, in: stack)
        let spring = try UniversityGraphAssertions.offering(101, in: stack)
        let design = try UniversityGraphAssertions.offering(102, in: stack)
        #expect(first.teacher?.id == 41 && first.room?.id == 51)
        #expect(spring.teacher?.id == 40 && spring.room?.id == 51)
        #expect(design.teacher?.id == 41 && design.room?.id == 50)
        #expect(try stack.count(UniTeacher.self) == 2)
        #expect(try stack.count(UniRoom.self) == 2)
    }

    @Test("A full offering snapshot removes only its surplus children and grades")
    func reconcileOwnedGraph() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        var expected = UniversityGraphFixture.university()
        try await stack.write(expected)
        expected.offerings[0].assignments.remove(at: 1)
        expected.offerings[0].enrollments[0].grades.remove(at: 1)
        expected.offerings[0].enrollments.remove(at: 1)
        var delta = expected
        delta.offerings = [expected.offerings[0]]
        try await stack.write(delta)
        try UniversityGraphAssertions.matches(expected, in: stack)
        #expect(try stack.count(UniAssignment.self) == 3)
        #expect(try stack.count(UniEnrollment.self) == 4)
        #expect(try stack.count(UniGrade.self) == 3)
        #expect(try stack.count(UniStudent.self) == 3)
        #expect(try UniversityGraphAssertions.offering(101, in: stack).enrollments?.count == 1)
        #expect(try UniversityGraphAssertions.offering(102, in: stack).enrollments?.count == 2)
    }

    @Test("Deleting one offering cascades only its assignments, enrollments and grades")
    func deleteOffering() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        var expected = UniversityGraphFixture.university()
        try await stack.write(expected)
        try await stack.importer.transaction { context in
            let request = NSFetchRequest<UniOffering>(entityName: "UniOffering")
            guard let offering = try context.fetch(request).first(where: { $0.id == 100 }) else {
                throw UniversityFixtureError.missingReference(entity: "UniOffering", id: 100)
            }
            context.delete(offering)
        }
        expected.offerings.remove(at: 0)
        try UniversityGraphAssertions.matches(expected, in: stack)
        #expect(try stack.count(UniCourse.self) == 2)
        #expect(try stack.count(UniSemester.self) == 2)
        #expect(try stack.count(UniStudent.self) == 3)
        #expect(try stack.count(UniTeacher.self) == 2)
        #expect(try stack.count(UniRoom.self) == 2)
    }
}
