import Testing

@MainActor
@Suite("Medical congress · sponsor snapshot")
struct SponsorSnapshotTests {
    @Test("Removing a sponsorship keeps the organization")
    func scenario() async throws {
        let stack = try CongressTestStack()
        try await stack.load()
        let initial = GraphCases.congress()
        try await stack.write(initial)
        var graph = GraphCases.congress()
        graph.events[0].sponsorIDs = []
        try await stack.write(graph)
        try GraphAssertions.matches(graph, in: stack)
        let sponsor = try #require(stack.fetch(Organization.self).first { $0.id == 2 })
        #expect(sponsor.sponsorships?.count == 1)
    }
}
