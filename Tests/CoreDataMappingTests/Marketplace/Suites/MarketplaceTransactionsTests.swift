import CoreData
import CoreDataMapping
import Testing

/// Verifies atomic order updates for invalid snapshots. A failure preserves
/// the previously saved graph of both orders.
///
/// - `duplicateItemRollback`: a duplicate local item ID rejects the batch.
/// - `missingProductRollback`: a missing product rolls back the order update.
@MainActor
@Suite("Marketplace · import transactions")
struct MarketplaceTransactionsTests {
    @Test("A duplicate item ID rolls back the order update")
    func duplicateItemRollback() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        let original = MarketplaceGraphFixture.marketplace()
        try await stack.write(original)
        var invalid = original
        invalid.orders[0].status = "changed"
        invalid.orders[0].items.append(.init(localID: 1, productID: 102, quantity: 9))
        invalid.orders = [invalid.orders[0]]
        await #expect(throws: CoreDataStorageError.duplicateOwnedIdentity(
            entityName: "MarketOrderItem", id: "1")) {
            try await stack.write(invalid)
        }
        try MarketplaceGraphAssertions.matches(original, in: stack)
        try MarketplaceGraphAssertions.assertOrder(500, status: "placed", itemProducts: [100, 101], in: stack)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
        #expect(try stack.count(MarketOrderItem.self) == 4)
    }

    @Test("A missing product rolls back the order without changing the other")
    func missingProductRollback() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        let original = MarketplaceGraphFixture.marketplace()
        try await stack.write(original)
        var invalid = original
        invalid.orders[0].status = "changed"
        invalid.orders[0].items[0].productID = 999
        invalid.orders = [invalid.orders[0]]
        await #expect(throws: MarketplaceFixtureError.missingReference(
            entity: "MarketProduct", id: 999)) {
            try await stack.write(invalid)
        }
        try MarketplaceGraphAssertions.matches(original, in: stack)

        try MarketplaceGraphAssertions.assertOrder(500, status: "placed", itemProducts: [100, 101], in: stack)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
        #expect(try stack.count(MarketOrderItem.self) == 4)
    }
}
