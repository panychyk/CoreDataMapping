import CoreData
import CoreDataMapping
import Testing

/// Verifies sequential imports and local identities of offering children.
/// A repeated snapshot preserves object IDs; updating one semester leaves
/// another unchanged.
///
/// - `sequentialImports`: two separate saves assemble the full graph.
/// - `repeatedImport`: roots, enrollments, assignments, and grades reuse object IDs.
/// - `isolatedSemesterUpdate`: changing one offering's grades and membership
///   leaves other offerings unchanged.
@MainActor
@Suite("University · import history")
struct UniversityImportHistoryTests {
    @Test("Separate offerings assemble a course across semesters")
    func sequentialImports() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let complete = UniversityGraphFixture.university()
        var first = complete
        first.offerings = [complete.offerings[0]]
        try await stack.write(first)
        try UniversityGraphAssertions.matches(first, in: stack)
        var second = complete
        second.offerings = Array(complete.offerings.dropFirst())
        try await stack.write(second)
        try UniversityGraphAssertions.matches(complete, in: stack)
    }

    @Test("A repeated snapshot reuses the same offering and owned rows")
    func repeatedImport() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        let graph = UniversityGraphFixture.university()
        try await stack.write(graph)
        let before = try rowIDs(in: stack)
        try await stack.write(graph)
        try UniversityGraphAssertions.matches(graph, in: stack)
        #expect(try rowIDs(in: stack) == before)
    }

    @Test("Updating autumn grades and membership leaves spring and design intact")
    func isolatedSemesterUpdate() async throws {
        let stack = try UniversityTestStack()
        try await stack.load()
        var expected = UniversityGraphFixture.university()
        try await stack.write(expected)
        let springBefore = try UniversityGraphAssertions.offering(101, in: stack).objectID
        expected.offerings[0].status = "closed"
        expected.offerings[0].assignments[1].title = "Final project"
        expected.offerings[0].enrollments[0].grades[0].score = 96
        expected.offerings[0].enrollments[1].status = "withdrawn"
        var delta = expected
        delta.offerings = [expected.offerings[0]]
        try await stack.write(delta)
        try UniversityGraphAssertions.matches(expected, in: stack)
        #expect(try UniversityGraphAssertions.offering(101, in: stack).objectID == springBefore)
        let spring = try UniversityGraphAssertions.offering(101, in: stack)
        let springEnrollment = try CoreDataStorage.ordered(spring.enrollments, as: UniEnrollment.self)[0]
        #expect((springEnrollment.grades?.allObjects.first as? UniGrade)?.score == 88)
    }

    private func rowIDs(in stack: UniversityTestStack) throws -> Set<NSManagedObjectID> {
        Set(try stack.fetch(UniOffering.self).map(\.objectID)
            + stack.fetch(UniAssignment.self).map(\.objectID)
            + stack.fetch(UniEnrollment.self).map(\.objectID)
            + stack.fetch(UniGrade.self).map(\.objectID))
    }
}
