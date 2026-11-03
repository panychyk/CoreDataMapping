import CoreDataMapping
import Testing

/// Verifies import integrity under local ID and relationship conflicts.
/// A failed batch rolls back root changes while earlier batches remain committed.
///
/// - `duplicateAssignmentRollback`: duplicate local assignment IDs reject the snapshot.
/// - `missingAssignmentRollback`: a grade cannot refer to another offering's assignment.
/// - `duplicateStudentRollback`: a student cannot enroll twice in one offering.
/// - `committedBatchSurvivesFailure`: failure of the second batch preserves the first.
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
