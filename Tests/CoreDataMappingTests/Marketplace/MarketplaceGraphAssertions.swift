import CoreData
import CoreDataMapping
import Testing

@MainActor
enum MarketplaceGraphAssertions {
    static func matches(_ graph: MarketplaceGraph, in stack: MarketplaceTestStack) throws {
        stack.resetViewContext()
        try matchesCatalog(graph, in: stack)
        try matchesOrders(graph, in: stack)
        try matchesReviews(graph, in: stack)
    }

    static func order(_ id: Int64, in stack: MarketplaceTestStack) throws -> MarketOrder {
        try #require(stack.fetch(MarketOrder.self).first { $0.id == id })
    }

    static func assertOrder(
        _ id: Int64, status: String, itemProducts: [Int64],
        in stack: MarketplaceTestStack
    ) throws {
        let value = try order(id, in: stack)
        #expect(value.status == status)
        let items = try CoreDataStorage.ordered(value.items, as: MarketOrderItem.self)
        #expect(items.map { $0.product?.id } == itemProducts.map(Optional.some))
        #expect(items.allSatisfy { $0.order === value })
        #expect(value.payments?.count == 1)
        #expect(value.shipments?.count == 1)
        #expect((value.payments?.allObjects.first as? MarketPayment)?.order === value)
        #expect((value.shipments?.allObjects.first as? MarketShipment)?.order === value)
    }

    private static func matchesCatalog(
        _ graph: MarketplaceGraph, in stack: MarketplaceTestStack
    ) throws {
        let buyers = try stack.fetch(MarketBuyer.self)
        let sellers = try stack.fetch(MarketSeller.self)
        let categories = try stack.fetch(MarketCategory.self)
        let warehouses = try stack.fetch(MarketWarehouse.self)
        let products = try stack.fetch(MarketProduct.self)
        let stocks = try stack.fetch(MarketStock.self)

        #expect(buyers.count == graph.buyers.count)
        #expect(sellers.count == graph.sellers.count)
        #expect(categories.count == graph.categories.count)
        #expect(warehouses.count == graph.warehouses.count)
        #expect(products.count == graph.products.count)
        #expect(stocks.count == graph.stocks.count)
        #expect(Set(buyers.map(\.id)) == Set(graph.buyers.map(\.id)))
        #expect(Set(sellers.map(\.id)) == Set(graph.sellers.map(\.id)))
        #expect(Set(categories.map(\.id)) == Set(graph.categories.map(\.id)))
        #expect(Set(warehouses.map(\.id)) == Set(graph.warehouses.map(\.id)))
        #expect(Set(products.map(\.id)) == Set(graph.products.map(\.id)))
        #expect(Set(stocks.map(\.id)) == Set(graph.stocks.map(\.id)))

        for snapshot in graph.buyers {
            #expect(buyers.first { $0.id == snapshot.id }?.name == snapshot.name)
        }
        for snapshot in graph.sellers {
            #expect(sellers.first { $0.id == snapshot.id }?.name == snapshot.name)
        }
        for snapshot in graph.categories {
            #expect(categories.first { $0.id == snapshot.id }?.name == snapshot.name)
        }
        for snapshot in graph.warehouses {
            #expect(warehouses.first { $0.id == snapshot.id }?.name == snapshot.name)
        }
        for snapshot in graph.products {
            let product = try #require(products.first { $0.id == snapshot.id })
            #expect(product.title == snapshot.title)
            #expect(product.seller?.id == snapshot.sellerID)
            let categoryIDs = Set((product.categories?.allObjects as? [MarketCategory] ?? []).map(\.id))
            #expect(categoryIDs == Set(snapshot.categoryIDs))
        }
        for snapshot in graph.stocks {
            let stock = try #require(stocks.first { $0.id == snapshot.id })
            #expect(stock.quantity == snapshot.quantity)
            #expect(stock.product?.id == snapshot.productID)
            #expect(stock.warehouse?.id == snapshot.warehouseID)
        }
    }

    private static func matchesOrders(
        _ graph: MarketplaceGraph, in stack: MarketplaceTestStack
    ) throws {
        let orders = try stack.fetch(MarketOrder.self)
        #expect(orders.count == graph.orders.count)
        #expect(Set(orders.map(\.id)) == Set(graph.orders.map(\.id)))

        for snapshot in graph.orders {
            let order = try #require(orders.first { $0.id == snapshot.id })
            #expect(order.status == snapshot.status)
            #expect(order.buyer?.id == snapshot.buyerID)

            let items = try CoreDataStorage.ordered(order.items, as: MarketOrderItem.self)
            #expect(items.map(\.localID) == snapshot.items.map(\.localID))
            for (item, wanted) in zip(items, snapshot.items) {
                #expect(item.order === order)
                #expect(item.product?.id == wanted.productID)
                #expect(item.quantity == wanted.quantity)
            }
            let payments = order.payments?.allObjects as? [MarketPayment] ?? []
            #expect(payments.count == snapshot.payments.count)
            #expect(Set(payments.map(\.localID)) == Set(snapshot.payments.map(\.localID)))
            for payment in payments {
                let wanted = try #require(snapshot.payments.first { $0.localID == payment.localID })
                #expect(payment.order === order)
                #expect(payment.amount == wanted.amount)
                #expect(payment.status == wanted.status)
            }
            let shipments = order.shipments?.allObjects as? [MarketShipment] ?? []
            #expect(shipments.count == snapshot.shipments.count)
            #expect(Set(shipments.map(\.localID)) == Set(snapshot.shipments.map(\.localID)))
            for shipment in shipments {
                let wanted = try #require(snapshot.shipments.first { $0.localID == shipment.localID })
                #expect(shipment.order === order)
                #expect(shipment.tracking == wanted.tracking)
                #expect(shipment.warehouse?.id == wanted.warehouseID)
            }
        }

        #expect(try stack.count(MarketOrderItem.self) == graph.orders.reduce(0) { $0 + $1.items.count })
        #expect(try stack.count(MarketPayment.self) == graph.orders.reduce(0) { $0 + $1.payments.count })
        #expect(try stack.count(MarketShipment.self) == graph.orders.reduce(0) { $0 + $1.shipments.count })
        #expect(try stack.fetch(MarketOrderItem.self).allSatisfy { $0.order != nil && $0.product != nil })
        #expect(try stack.fetch(MarketPayment.self).allSatisfy { $0.order != nil })
        #expect(try stack.fetch(MarketShipment.self).allSatisfy { $0.order != nil && $0.warehouse != nil })
    }

    private static func matchesReviews(
        _ graph: MarketplaceGraph, in stack: MarketplaceTestStack
    ) throws {
        let reviews = try stack.fetch(MarketReview.self)
        #expect(reviews.count == graph.reviews.count)
        #expect(Set(reviews.map(\.id)) == Set(graph.reviews.map(\.id)))
        for snapshot in graph.reviews {
            let review = try #require(reviews.first { $0.id == snapshot.id })
            #expect(review.rating == snapshot.rating)
            #expect(review.buyer?.id == snapshot.buyerID)
            #expect(review.product?.id == snapshot.productID)
        }
    }
}
