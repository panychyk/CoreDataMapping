import Testing

@MainActor
@Suite("Medical congress · multistage history")
struct MultistageHistoryTests {
    @Test("Shared and owned relationships remain correct after four saves")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let complete = GraphCases.congress()

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
