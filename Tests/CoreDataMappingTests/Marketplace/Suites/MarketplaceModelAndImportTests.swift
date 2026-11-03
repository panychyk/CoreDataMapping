import CoreData
import CoreDataMapping
import Testing

/// Verifies the shared Core Data model and first import of the full marketplace
/// graph: sellers, products, categories, warehouses, orders, and reviews.
///
/// - `schemaRules`: every relationship has an inverse and owned and shared links
///   have the appropriate delete rules.
/// - `fullGraph`: all 11 entity types and their links survive a read-context reset.
@MainActor
@Suite("Marketplace · model and initial import")
struct MarketplaceModelAndImportTests {
    @Test("Shared model contains the marketplace entities and relationship rules")
    func schemaRules() throws {
        let url = try #require(Bundle.module.url(forResource: "TestModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: url))
        #expect(model.entities.count == 49)
        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.inverseRelationship?.inverseRelationship === relationship)
            }
        }
        for (entityName, relationshipName) in [
            ("MarketSeller", "products"), ("MarketProduct", "stocks"),
            ("MarketProduct", "reviews"), ("MarketWarehouse", "stocks"),
            ("MarketOrder", "items"), ("MarketOrder", "payments"),
            ("MarketOrder", "shipments"),
        ] {
            let entity = try #require(model.entitiesByName[entityName])
            #expect(entity.relationshipsByName[relationshipName]?.deleteRule == .cascadeDeleteRule)
        }
        for (entityName, relationshipName) in [
            ("MarketProduct", "categories"), ("MarketProduct", "orderItems"),
            ("MarketBuyer", "orders"), ("MarketWarehouse", "shipments"),
        ] {
            let entity = try #require(model.entitiesByName[entityName])
            #expect(entity.relationshipsByName[relationshipName]?.deleteRule == .nullifyDeleteRule)
        }
    }

    @Test("A full marketplace graph survives context reset")
    func fullGraph() async throws {
        let stack = try MarketplaceTestStack()
        try await stack.load()
        let graph = MarketplaceGraphFixture.marketplace()
        try await stack.write(graph)
        try MarketplaceGraphAssertions.matches(graph, in: stack)

        #expect(try stack.count(MarketBuyer.self) == 2)
        #expect(try stack.count(MarketSeller.self) == 2)
        #expect(try stack.count(MarketProduct.self) == 3)
        #expect(try stack.count(MarketCategory.self) == 2)
        #expect(try stack.count(MarketWarehouse.self) == 2)
        #expect(try stack.count(MarketStock.self) == 3)
        #expect(try stack.count(MarketOrder.self) == 2)
        #expect(try stack.count(MarketOrderItem.self) == 4)
        #expect(try stack.count(MarketPayment.self) == 2)
        #expect(try stack.count(MarketShipment.self) == 2)
        #expect(try stack.count(MarketReview.self) == 2)

        let lamp = try #require(stack.fetch(MarketProduct.self).first { $0.id == 100 })
        #expect(lamp.seller?.id == 10)
        #expect(Set((lamp.categories?.allObjects as? [MarketCategory] ?? []).map(\.id)) == [20, 21])
        #expect(lamp.orderItems?.count == 2)
        #expect(lamp.reviews?.count == 2)
        let seller = try #require(stack.fetch(MarketSeller.self).first { $0.id == 10 })
        #expect(Set((seller.products?.allObjects as? [MarketProduct] ?? []).map(\.id)) == [100, 101])
        let category = try #require(stack.fetch(MarketCategory.self).first { $0.id == 21 })
        #expect(Set((category.products?.allObjects as? [MarketProduct] ?? []).map(\.id)) == [100, 102])
        let warehouse = try #require(stack.fetch(MarketWarehouse.self).first { $0.id == 30 })
        #expect(warehouse.stocks?.count == 1)
        #expect(warehouse.shipments?.count == 1)
        let buyer = try #require(stack.fetch(MarketBuyer.self).first { $0.id == 1 })
        #expect(buyer.orders?.count == 1)
        #expect(buyer.reviews?.count == 1)
        let stock = try #require(stack.fetch(MarketStock.self).first { $0.id == 200 })
        #expect(stock.product?.id == 100)
        #expect(stock.warehouse?.id == 30)
        #expect(stock.quantity == 12)
        let review = try #require(stack.fetch(MarketReview.self).first { $0.id == 600 })
        #expect(review.buyer?.id == 1)
        #expect(review.product?.id == 100)
        try MarketplaceGraphAssertions.assertOrder(500, status: "placed", itemProducts: [100, 101], in: stack)
        try MarketplaceGraphAssertions.assertOrder(501, status: "placed", itemProducts: [100, 102], in: stack)
    }
}
