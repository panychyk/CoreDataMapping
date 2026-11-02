import CoreData
import CoreDataMapping
import Testing

/// Перевіряє життєвий цикл дітей конкретного замовлення. Вилучення
/// платежу, доставки або цілого замовлення не видаляє спільні товари й склади.
///
/// - `orderChildrenSnapshot`: повний snapshot видаляє платіж і доставку лише
///   першого замовлення.
/// - `orderDeletion`: каскадне видалення прибирає його позиції, платежі й
///   доставки, залишаючи друге замовлення.
@MainActor
@Suite("Marketplace · owned lifecycle")
struct MarketplaceOwnedLifecycleTests {
    @Test("Removing payment and shipment affects only their order")
    func orderChildrenSnapshot() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        var expected = MarketplaceGraphFixture.marketplace()
        try await stack.write(expected)
        expected.orders[0].payments = []
        expected.orders[0].shipments = []
        var update = expected
        update.orders = [expected.orders[0]]
        try await stack.write(update)
        try MarketplaceGraphAssertions.matches(expected, in: stack)

        let first = try MarketplaceGraphAssertions.order(500, in: stack)
        let second = try MarketplaceGraphAssertions.order(501, in: stack)
        #expect(first.payments?.count == 0)
        #expect(first.shipments?.count == 0)
        #expect(second.payments?.count == 1)
        #expect(second.shipments?.count == 1)
        #expect(try stack.count(MarketPayment.self) == 1)
        #expect(try stack.count(MarketShipment.self) == 1)
        #expect(try stack.count(MarketWarehouse.self) == 2)
    }

    @Test("Deleting an order removes only its owned rows")
    func orderDeletion() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        var expected = MarketplaceGraphFixture.marketplace()
        try await stack.write(expected)
        try await stack.importer.transaction { context in
            let request = NSFetchRequest<MarketOrder>(entityName: "MarketOrder")
            guard let first = try context.fetch(request).first(where: { $0.id == 500 }) else {
                throw MarketplaceFixtureError.missingReference(entity: "MarketOrder", id: 500)
            }
            context.delete(first)
        }
        expected.orders.remove(at: 0)
        try MarketplaceGraphAssertions.matches(expected, in: stack)

        #expect(try stack.count(MarketOrder.self) == 1)
        #expect(try stack.count(MarketOrderItem.self) == 2)
        #expect(try stack.count(MarketPayment.self) == 1)
        #expect(try stack.count(MarketShipment.self) == 1)
        #expect(try stack.count(MarketProduct.self) == 3)
        #expect(try stack.count(MarketReview.self) == 2)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
    }
}
