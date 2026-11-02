import CoreData
import CoreDataMapping

enum MarketplaceFixtureError: Error, Equatable {
    case missingReference(entity: String, id: Int64)
}

enum MarketplaceGraphWriter {
    // Products, categories, buyers and warehouses are shared. Items, payments
    // and shipments are reconciled only within their owning order.
    static func write(_ graphs: [MarketplaceGraph], using storage: CoreDataStorage) throws {
        let buyers = try storage.upsert(
            ids: graphs.flatMap { $0.buyers.map(\.id) }, identifiedBy: MarketBuyer.identity)
        let sellers = try storage.upsert(
            ids: graphs.flatMap { $0.sellers.map(\.id) }, identifiedBy: MarketSeller.identity)
        let categories = try storage.upsert(
            ids: graphs.flatMap { $0.categories.map(\.id) }, identifiedBy: MarketCategory.identity)
        let warehouses = try storage.upsert(
            ids: graphs.flatMap { $0.warehouses.map(\.id) }, identifiedBy: MarketWarehouse.identity)
        let products = try storage.upsert(
            ids: graphs.flatMap { $0.products.map(\.id) },
            identifiedBy: MarketProduct.identity, prefetching: ["categories"])
        let stocks = try storage.upsert(
            ids: graphs.flatMap { $0.stocks.map(\.id) }, identifiedBy: MarketStock.identity)
        let orders = try storage.upsert(
            ids: graphs.flatMap { $0.orders.map(\.id) },
            identifiedBy: MarketOrder.identity,
            prefetching: ["items", "payments", "shipments"])
        let reviews = try storage.upsert(
            ids: graphs.flatMap { $0.reviews.map(\.id) }, identifiedBy: MarketReview.identity)

        for graph in graphs {
            for value in graph.buyers {
                try required(buyers, id: value.id, entity: "MarketBuyer").name = value.name
            }
            for value in graph.sellers {
                try required(sellers, id: value.id, entity: "MarketSeller").name = value.name
            }
            for value in graph.categories {
                try required(categories, id: value.id, entity: "MarketCategory").name = value.name
            }
            for value in graph.warehouses {
                try required(warehouses, id: value.id, entity: "MarketWarehouse").name = value.name
            }
            for value in graph.products {
                let product = try required(products, id: value.id, entity: "MarketProduct")
                product.title = value.title
                product.seller = try required(sellers, id: value.sellerID, entity: "MarketSeller")
                product.categories = NSSet(array: Array(try storage.replaceUnordered(
                    with: try value.categoryIDs.map {
                        try required(categories, id: $0, entity: "MarketCategory")
                    })))
            }
            for value in graph.stocks {
                let stock = try required(stocks, id: value.id, entity: "MarketStock")
                stock.quantity = value.quantity
                stock.product = try required(products, id: value.productID, entity: "MarketProduct")
                stock.warehouse = try required(
                    warehouses, id: value.warehouseID, entity: "MarketWarehouse")
            }
            for value in graph.reviews {
                let review = try required(reviews, id: value.id, entity: "MarketReview")
                review.rating = value.rating
                review.buyer = try required(buyers, id: value.buyerID, entity: "MarketBuyer")
                review.product = try required(products, id: value.productID, entity: "MarketProduct")
            }
            for value in graph.orders {
                let order = try required(orders, id: value.id, entity: "MarketOrder")
                order.status = value.status
                order.buyer = try required(buyers, id: value.buyerID, entity: "MarketBuyer")
                try write(value, to: order, products: products,
                          warehouses: warehouses, using: storage)
            }
        }
    }

    private static func write(
        _ value: OrderValue,
        to order: MarketOrder,
        products: [Int64: MarketProduct],
        warehouses: [Int64: MarketWarehouse],
        using storage: CoreDataStorage
    ) throws {
        let items = try storage.reconcileOwned(
            value.items, current: try CoreDataStorage.ordered(order.items, as: MarketOrderItem.self),
            dtoId: \OrderItemValue.localID, entityId: \MarketOrderItem.localID,
            create: { try storage.insert(MarketOrderItem.self) }
        ) { item, snapshot in
            item.localID = snapshot.localID
            item.quantity = snapshot.quantity
            item.product = try required(products, id: snapshot.productID, entity: "MarketProduct")
        }
        order.items = try storage.replace(with: items)

        let payments = try storage.reconcileOwned(
            value.payments, current: try objects(order.payments),
            dtoId: \PaymentValue.localID, entityId: \MarketPayment.localID,
            create: { try storage.insert(MarketPayment.self) }
        ) { payment, snapshot in
            payment.localID = snapshot.localID
            payment.amount = snapshot.amount
            payment.status = snapshot.status
        }
        order.payments = NSSet(array: payments)

        let shipments = try storage.reconcileOwned(
            value.shipments, current: try objects(order.shipments),
            dtoId: \ShipmentValue.localID, entityId: \MarketShipment.localID,
            create: { try storage.insert(MarketShipment.self) }
        ) { shipment, snapshot in
            shipment.localID = snapshot.localID
            shipment.tracking = snapshot.tracking
            shipment.warehouse = try required(
                warehouses, id: snapshot.warehouseID, entity: "MarketWarehouse")
        }
        order.shipments = NSSet(array: shipments)
    }

    private static func objects<Entity: NSManagedObject>(_ set: NSSet?) throws -> [Entity] {
        guard let set else { return [] }
        guard let values = set.allObjects as? [Entity] else {
            throw CoreDataStorageError.unexpectedRelationshipEntityType(
                expectedType: String(describing: Entity.self))
        }
        return values
    }

    private static func required<Value>(
        _ values: [Int64: Value], id: Int64, entity: String
    ) throws -> Value {
        guard let value = values[id] else {
            throw MarketplaceFixtureError.missingReference(entity: entity, id: id)
        }
        return value
    }
}
