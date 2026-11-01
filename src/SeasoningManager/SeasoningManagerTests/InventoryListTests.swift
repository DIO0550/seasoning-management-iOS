import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct InventoryListTests {
    @Test func inventoryKeepsEachCurrentItemAndExcludesConsumedAndUnknownStatuses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let unopened = Item(product: product)
        let secondUnopened = Item(product: product)
        let inUse = Item(product: product, status: .inUse)
        let consumed = Item(product: product, status: .consumed)
        let unknown = Item(product: product)
        unknown.statusRawValue = "futureStatus"
        context.insert(product)
        for item in [unopened, secondUnopened, inUse, consumed, unknown] {
            context.insert(item)
        }
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(InventoryListView.descriptor())

        #expect(Set(items.map(\.id)) == Set([unopened.id, secondUnopened.id, inUse.id]))
        #expect(items.filter { $0.status == .unopened }.count == 2)
        #expect(items.filter { $0.status == .inUse }.count == 1)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 5)
        #expect(!reader.hasChanges)
    }

    @Test(arguments: [[String](), ["consumed"], ["futureStatus"], [""], ["consumed", "futureStatus", ""]])
    func inventoryIsEmptyWithoutKnownCurrentItems(_ rawValues: [String]) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "みそ", type: "調味料")
        context.insert(product)
        for rawValue in rawValues {
            let item = Item(product: product)
            item.statusRawValue = rawValue
            context.insert(item)
        }
        try context.save()

        let reader = ModelContext(container)
        #expect(try reader.fetch(InventoryListView.descriptor()).isEmpty)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == rawValues.count)
    }

    @Test func inventoryReflectsSavedOpeningConsumptionAndDeletion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let first = Item(product: product)
        let second = Item(product: product)
        context.insert(product)
        context.insert(first)
        context.insert(second)
        try context.save()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let actions = ItemActions(context: context)

        try actions.open(first, openingDate: now, now: now).get()
        let openingReader = ModelContext(container)
        let afterOpening = try openingReader.fetch(InventoryListView.descriptor())
        #expect(Set(afterOpening.map(\.id)) == Set([first.id, second.id]))
        #expect(afterOpening.first { $0.id == first.id }?.status == .inUse)
        #expect(afterOpening.first { $0.id == second.id }?.status == .unopened)

        try actions.consume(first, consumedDate: now, now: now).get()
        let consumptionReader = ModelContext(container)
        let afterConsumption = try consumptionReader.fetch(InventoryListView.descriptor())
        #expect(afterConsumption.map(\.id) == [second.id])

        try actions.delete(second, confirmed: true).get()
        let reader = ModelContext(container)
        #expect(try reader.fetch(InventoryListView.descriptor()).isEmpty)
        let history = try #require(try reader.fetch(FetchDescriptor<Item>()).first)
        #expect(history.id == first.id)
        #expect(history.status == .consumed)
    }

    @Test func missingProductRelationshipDoesNotHideCurrentItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let item = Item(product: product)
        context.insert(product)
        context.insert(item)
        item.product = nil
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(InventoryListView.descriptor())
        #expect(items.map(\.id) == [item.id])
        #expect(items.first?.product == nil)
        #expect(!reader.hasChanges)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
