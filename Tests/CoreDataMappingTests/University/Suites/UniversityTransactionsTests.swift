import CoreDataMapping
import Testing

/// Перевіряє цілісність імпорту при конфліктах локальних ID і зв’язків.
/// Помилковий batch відкочується разом зі змінами root, а попередні batch збережені.
///
/// - `duplicateAssignmentRollback`: однакові локальні ID завдань відхиляють snapshot.
/// - `missingAssignmentRollback`: оцінка не може посилатися на завдання іншого проведення.
/// - `duplicateStudentRollback`: студент не може бути записаний двічі на одне проведення.
/// - `committedBatchSurvivesFailure`: помилка другого batch не відкочує перший.
@MainActor
@Suite("University · import transactions")
struct UniversityTransactionsTests {
    @Test("Duplicate scoped assignment IDs roll back the offering")
    func duplicateAssignmentRollback() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let original = UniversityGraphFixture.university()
        try await stack.write(original)
        var invalid = original
        invalid.offerings[0].status = "changed"
        invalid.offerings[0].assignments.append(.init(localID: 1, title: "Duplicate"))
        invalid.offerings = [invalid.offerings[0]]
        await #expect(throws: CoreDataStorageError.duplicateOwnedIdentity(
            entityName: "UniAssignment", id: "1")) {
            try await stack.write(invalid)
        }
        try UniversityGraphAssertions.matches(original, in: stack)
    }

    @Test("A grade cannot reference an assignment in another offering")
    func missingAssignmentRollback() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let original = UniversityGraphFixture.university()
        try await stack.write(original)
        var invalid = original
        invalid.offerings[1].status = "changed"
        // Local ID 2 belongs to autumn offering 100, not spring offering 101.
        invalid.offerings[1].enrollments[0].grades[0].assignmentID = 2
        invalid.offerings = [invalid.offerings[1]]
        await #expect(throws: UniversityFixtureError.missingReference(
            entity: "UniAssignment", id: 2)) {
            try await stack.write(invalid)
        }
        try UniversityGraphAssertions.matches(original, in: stack)
    }

    @Test("A student cannot have two enrollments in one offering")
    func duplicateStudentRollback() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let original = UniversityGraphFixture.university()
        try await stack.write(original)
        var invalid = original
        invalid.offerings[0].enrollments.append(
            .init(localID: 3, studentID: 30, status: "active", grades: []))
        invalid.offerings = [invalid.offerings[0]]
        await #expect(throws: UniversityFixtureError.duplicateStudent(
            offeringID: 100, studentID: 30)) {
            try await stack.write(invalid)
        }
        try UniversityGraphAssertions.matches(original, in: stack)
    }

    @Test("An earlier saved batch survives a later invalid offering")
    func committedBatchSurvivesFailure() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let complete = UniversityGraphFixture.university()
        var first = complete
        first.offerings = [complete.offerings[0]]
        var invalid = complete
        invalid.offerings = [complete.offerings[1]]
        invalid.offerings[0].enrollments[0].grades[0].assignmentID = 999
        await #expect(throws: UniversityFixtureError.missingReference(
            entity: "UniAssignment", id: 999)) {
            try await stack.importer.write([first, invalid], batchSize: 1) { batch, storage in
                try UniversityGraphWriter.write(batch, using: storage)
            }
        }
        try UniversityGraphAssertions.matches(first, in: stack)
    }
}
