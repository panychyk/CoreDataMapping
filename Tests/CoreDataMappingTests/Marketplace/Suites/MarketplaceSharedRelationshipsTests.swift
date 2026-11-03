import CoreData
import CoreDataMapping
import Testing

/// Verifies shared product links to categories, warehouses, and orders after
/// separate updates.
///
/// - `categoryMembership`: changing product categories preserves the categories
///   and the product's use in both orders.
/// - `stockUpdate`: updating stock at one warehouse preserves the other
///   warehouse's stock and the orders.
@MainActor
@Suite("Marketplace · shared relationships")
struct MarketplaceSharedRelationshipsTests {
    @Test("Replacing product categories keeps shared categories and both orders")
    func categoryMembership() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        var graph = MarketplaceGraphFixture.marketplace()
        try await stack.write(graph)
        graph.products[0].categoryIDs = [21]
        try await stack.write(graph)
        try MarketplaceGraphAssertions.matches(graph, in: stack)

        let lamp = try #require(stack.fetch(MarketProduct.self).first { $0.id == 100 })
        #expect(Set((lamp.categories?.allObjects as? [MarketCategory] ?? []).map(\.id)) == [21])
        #expect(try stack.count(MarketCategory.self) == 2)
        #expect(lamp.orderItems?.count == 2)
        try MarketplaceGraphAssertions.assertOrder(500, status: "placed", itemProducts: [100, 101], in: stack)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
    }

    @Test("Stock updates reuse the row and do not change other warehouses")
    func stockUpdate() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        var graph = MarketplaceGraphFixture.marketplace()
        try await stack.write(graph)
        graph.stocks[0].quantity = 7
        try await stack.write(graph)
        try MarketplaceGraphAssertions.matches(graph, in: stack)

        let stocks = try stack.fetch(MarketStock.self)
        #expect(stocks.count == 3)
        #expect(stocks.first { $0.id == 200 }?.quantity == 7)
        #expect(stocks.first { $0.id == 201 }?.quantity == 4)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
    }
}
