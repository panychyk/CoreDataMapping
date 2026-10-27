import Testing

@MainActor
@Suite("Medical congress · shared room")
struct SharedRoomTests {
    @Test("Changing one meeting room keeps other bookings")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].appointments[0].roomID = 21
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let room = try #require(stack.fetch(Room.self).first { $0.id == 22 })
        #expect(room.appointments?.count == 2)
    }
}
