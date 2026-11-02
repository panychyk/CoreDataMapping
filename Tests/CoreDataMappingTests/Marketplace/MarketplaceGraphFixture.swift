struct MarketplaceGraph: Sendable {
    var buyers: [BuyerValue]
    var sellers: [SellerValue]
    var categories: [CategoryValue]
    var warehouses: [WarehouseValue]
    var products: [ProductValue]
    var stocks: [StockValue]
    var orders: [OrderValue]
    var reviews: [ReviewValue]
}

struct BuyerValue: Sendable {
    var id: Int64
    var name: String
}
struct SellerValue: Sendable {
    var id: Int64
    var name: String
}
struct CategoryValue: Sendable {
    var id: Int64
    var name: String
}
struct WarehouseValue: Sendable {
    var id: Int64
    var name: String
}
struct ProductValue: Sendable {
    var id: Int64
    var title: String
    var sellerID: Int64
    var categoryIDs: [Int64]
}
struct StockValue: Sendable {
    var id: Int64
    var productID: Int64
    var warehouseID: Int64
    var quantity: Int64
}
struct OrderValue: Sendable {
    var id: Int64
    var buyerID: Int64
    var status: String
    var items: [OrderItemValue]
    var payments: [PaymentValue]
    var shipments: [ShipmentValue]
}
struct OrderItemValue: Sendable {
    var localID: Int64
    var productID: Int64
    var quantity: Int64
}
struct PaymentValue: Sendable {
    var localID: Int64
    var amount: Int64
    var status: String
}
struct ShipmentValue: Sendable {
    var localID: Int64
    var warehouseID: Int64
    var tracking: String
}
struct ReviewValue: Sendable {
    var id: Int64
    var buyerID: Int64
    var productID: Int64
    var rating: Int64
}

enum MarketplaceGraphFixture {
    static func marketplace() -> MarketplaceGraph {
        MarketplaceGraph(
            buyers: [
                .init(id: 1, name: "Ada"),
                .init(id: 2, name: "Bohdan"),
            ],
            sellers: [
                .init(id: 10, name: "North Shop"),
                .init(id: 11, name: "South Shop"),
            ],
            categories: [
                .init(id: 20, name: "Electronics"),
                .init(id: 21, name: "Home"),
            ],
            warehouses: [
                .init(id: 30, name: "Zagreb"),
                .init(id: 31, name: "Split"),
            ],
            products: [
                .init(id: 100, title: "Lamp", sellerID: 10, categoryIDs: [20, 21]),
                .init(id: 101, title: "Cable", sellerID: 10, categoryIDs: [20]),
                .init(id: 102, title: "Shelf", sellerID: 11, categoryIDs: [21]),
            ],
            stocks: [
                .init(id: 200, productID: 100, warehouseID: 30, quantity: 12),
                .init(id: 201, productID: 100, warehouseID: 31, quantity: 4),
                .init(id: 202, productID: 102, warehouseID: 31, quantity: 6),
            ],
            orders: [
                .init(
                    id: 500, buyerID: 1, status: "placed",
                    items: [
                        .init(localID: 1, productID: 100, quantity: 2),
                        .init(localID: 2, productID: 101, quantity: 1),
                    ],
                    payments: [.init(localID: 1, amount: 2500, status: "authorized")],
                    shipments: [.init(localID: 1, warehouseID: 30, tracking: "ZA-1")]
                ),
                .init(
                    id: 501, buyerID: 2, status: "placed",
                    items: [
                        .init(localID: 1, productID: 100, quantity: 1),
                        .init(localID: 2, productID: 102, quantity: 1),
                    ],
                    payments: [.init(localID: 1, amount: 1800, status: "captured")],
                    shipments: [.init(localID: 1, warehouseID: 31, tracking: "ST-1")]
                ),
            ],
            reviews: [
                .init(id: 600, buyerID: 1, productID: 100, rating: 5),
                .init(id: 601, buyerID: 2, productID: 100, rating: 4),
            ]
        )
    }
}
