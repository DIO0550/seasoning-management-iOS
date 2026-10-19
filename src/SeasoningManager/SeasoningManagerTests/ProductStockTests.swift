import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ProductStockTests {
    @Test(arguments: ["", "futureStatus"])
    func savedStockExcludesConsumedAndUnknownStatuses(_ rawValue: String) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        context.insert(product)

        for status in [ItemStatus.unopened, .unopened, .inUse, .consumed] {
            context.insert(Item(product: product, status: status))
        }
        let unknown = Item(product: product)
        unknown.statusRawValue = rawValue
        context.insert(unknown)
        try context.save()

        // 保存した個体の逆リレーションから集計し、未知の保存値を補完しない。
        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<Product>()).first)
        let items = try #require(saved.items)
        let savedUnknown = try #require(items.first { $0.id == unknown.id })

        #expect(items.count == 5)
        #expect(items.allSatisfy { $0.product?.id == saved.id })
        #expect(saved.stockCounts.unopened == 2)
        #expect(saved.stockCounts.inUse == 1)
        #expect(savedUnknown.statusRawValue == rawValue)
        #expect(savedUnknown.status == nil)
        #expect(!reader.hasChanges)
    }

    @Test func sameNameProductsKeepTheirOwnStock() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = Product(name: "しょうゆ", type: "調味料")
        let second = Product(name: "しょうゆ", type: "調味料")
        context.insert(first)
        context.insert(second)
        context.insert(Item(product: first))
        context.insert(Item(product: first))
        context.insert(Item(product: second, status: .inUse))
        try context.save()

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        let savedFirst = try #require(products.first { $0.id == first.id })
        let savedSecond = try #require(products.first { $0.id == second.id })

        #expect(savedFirst.stockCounts.unopened == 2)
        #expect(savedFirst.stockCounts.inUse == 0)
        #expect(savedSecond.stockCounts.unopened == 0)
        #expect(savedSecond.stockCounts.inUse == 1)
    }

    @Test(arguments: [[String](), ["consumed"], ["futureStatus"], [""]])
    func productsWithoutCurrentStockReportBothZeros(_ rawValues: [String]) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        context.insert(product)

        for rawValue in rawValues {
            let item = Item(product: product)
            item.statusRawValue = rawValue
            context.insert(item)
        }
        try context.save()

        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<Product>()).first)

        #expect((saved.items ?? []).count == rawValues.count)
        #expect(saved.stockCounts.unopened == 0)
        #expect(saved.stockCounts.inUse == 0)
    }

    @Test func missingItemRelationshipReportsBothZeros() {
        let product = Product(name: "しょうゆ", type: "調味料")

        #expect(product.items == nil)
        #expect(product.stockCounts.unopened == 0)
        #expect(product.stockCounts.inUse == 0)
    }

    @Test func stockRecalculatesAfterStatusChangesAndDeletion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let unopened = Item(product: product)
        let inUse = Item(product: product, status: .inUse)
        context.insert(product)
        context.insert(unopened)
        context.insert(inUse)
        try context.save()

        #expect(product.stockCounts.unopened == 1)
        #expect(product.stockCounts.inUse == 1)

        unopened.statusRawValue = ItemStatus.inUse.rawValue
        try context.save()

        #expect(product.stockCounts.unopened == 0)
        #expect(product.stockCounts.inUse == 2)

        inUse.statusRawValue = ItemStatus.consumed.rawValue
        try context.save()

        #expect(product.stockCounts.unopened == 0)
        #expect(product.stockCounts.inUse == 1)

        context.delete(unopened)
        try context.save()

        #expect(product.stockCounts.unopened == 0)
        #expect(product.stockCounts.inUse == 0)

        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<Product>()).first)

        #expect(saved.items?.map(\.id) == [inUse.id])
        #expect(saved.stockCounts.unopened == 0)
        #expect(saved.stockCounts.inUse == 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
