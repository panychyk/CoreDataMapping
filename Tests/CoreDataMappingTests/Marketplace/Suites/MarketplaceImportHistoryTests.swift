import CoreData
import CoreDataMapping
import Testing

/// Перевіряє повторний імпорт і незалежність двох замовлень, які мають
/// спільний товар та однакові локальні ID позицій.
///
/// - `isolatedOrderUpdate`: оновлення позицій, платежу й доставки першого
///   замовлення не змінює друге.
/// - `repeatedImport`: повторний snapshot використовує ті самі root і child rows.
@MainActor
@Suite("Marketplace · import history")
struct MarketplaceImportHistoryTests {
    @Test("Updating one order reconciles only its owned rows")
    func isolatedOrderUpdate() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        var expected = MarketplaceGraphFixture.marketplace()
        try await stack.write(expected)
        expected.orders[0].status = "shipped"
        expected.orders[0].items = [.init(localID: 1, productID: 100, quantity: 5)]
        expected.orders[0].payments[0].status = "refunded"
        expected.orders[0].shipments[0].tracking = "ZA-2"
        var update = expected
        update.orders = [expected.orders[0]]
        try await stack.write(update)
        try MarketplaceGraphAssertions.matches(expected, in: stack)

        try MarketplaceGraphAssertions.assertOrder(500, status: "shipped", itemProducts: [100], in: stack)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
        let first = try MarketplaceGraphAssertions.order(500, in: stack)
        let second = try MarketplaceGraphAssertions.order(501, in: stack)
        #expect((first.items?[0] as? MarketOrderItem)?.quantity == 5)
        #expect((second.items?[0] as? MarketOrderItem)?.quantity == 1)
        #expect((first.payments?.allObjects.first as? MarketPayment)?.status == "refunded")
        #expect((second.payments?.allObjects.first as? MarketPayment)?.status == "captured")
        #expect((first.shipments?.allObjects.first as? MarketShipment)?.tracking == "ZA-2")
        #expect((second.shipments?.allObjects.first as? MarketShipment)?.tracking == "ST-1")
        #expect(try stack.count(MarketOrderItem.self) == 3)
        #expect(try stack.count(MarketProduct.self) == 3)
        #expect(try stack.count(MarketStock.self) == 3)
    }

    @Test("Repeated snapshots reuse order children with the same local IDs")
    func repeatedImport() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        let graph = MarketplaceGraphFixture.marketplace()
        try await stack.write(graph)
        let originalOrder = try MarketplaceGraphAssertions.order(500, in: stack).objectID
        let originalItems = try CoreDataStorage.ordered(
            MarketplaceGraphAssertions.order(500, in: stack).items, as: MarketOrderItem.self
        ).map(\.objectID)
        try await stack.write(graph)
        try MarketplaceGraphAssertions.matches(graph, in: stack)

        #expect(try MarketplaceGraphAssertions.order(500, in: stack).objectID == originalOrder)
        #expect(try CoreDataStorage.ordered(
            MarketplaceGraphAssertions.order(500, in: stack).items, as: MarketOrderItem.self
        ).map(\.objectID) == originalItems)
        #expect(try stack.count(MarketOrderItem.self) == 4)
        #expect(try stack.count(MarketPayment.self) == 2)
        #expect(try stack.count(MarketShipment.self) == 2)
    }
}
