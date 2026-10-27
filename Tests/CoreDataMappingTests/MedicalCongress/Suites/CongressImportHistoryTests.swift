import Testing

/// Перевіряє, що після кількох імпортів дані конгресу залишаються повними й
/// актуальними. Повторний імпорт не створює дублікатів, а оновлення однієї
/// події не змінює іншу.
///
/// - `sequentialImports`: дві порції створюють цілісний граф двох подій.
/// - `repeatedImport`: повторний snapshot використовує ті самі записи зустрічей.
/// - `isolatedUpdate`: оновлення першої події не змінює другу.
/// - `multistageHistory`: після чотирьох збережень зв’язки актуальні, а дочірні
///   записи не залишаються «сиротами».
@MainActor
@Suite("Medical congress · import history")
struct CongressImportHistoryTests {
    @Test("Two committed imports assemble the full congress")
    func sequentialImports() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let complete = CongressGraphFixture.congress()
        var first = complete
        first.events = [complete.events[0]]
        try await stack.write(first)
        try GraphAssertions.matches(first, in: stack)
        var second = complete
        second.events = [complete.events[1]]
        try await stack.write(second)
        try GraphAssertions.matches(complete, in: stack)
    }

    @Test("Repeated full snapshots reuse rows")
    func repeatedImport() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        let before = Set(try stack.fetch(Appointment.self).map { $0.objectID })
        try await stack.write(initial)
        try GraphAssertions.matches(initial, in: stack)
        let after = Set(try stack.fetch(Appointment.self).map { $0.objectID })
        #expect(before == after)
    }

    @Test("Updating one event preserves the other event")
    func isolatedUpdate() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = CongressGraphFixture.congress()
        try await stack.write(initial)
        var graph = CongressGraphFixture.congress()
        graph.events[0].title = "Research Day revised"
        graph.events[0].tracks[0].sessions[0].title = "Updated therapies"
        graph.events[0].appointments[0].participants[0].status = "arrived"
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
    }

    @Test("Shared and owned relationships remain correct after four saves")
    func multistageHistory() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let complete = CongressGraphFixture.congress()

        var first = complete
        first.events = [complete.events[0]]
        try await stack.write(first)
        try GraphAssertions.matches(first, in: stack)

        var second = complete
        second.events = [complete.events[1]]
        try await stack.write(second)
        try GraphAssertions.matches(complete, in: stack)

        var revised = complete
        revised.events[0].appointments[0].roomID = 21
        revised.events[0].appointments[0].participants.removeAll { $0.personID == 12 }
        revised.events[0].tracks[0].sessions[0].resourceIDs = [31]
        try await stack.write(revised)
        try GraphAssertions.matches(revised, in: stack)

        revised.events[0].appointments.remove(at: 1)
        revised.events[0].registrations[0].checkInIDs.append(2)
        try await stack.write(revised)
        try GraphAssertions.matches(revised, in: stack)
    }
}
