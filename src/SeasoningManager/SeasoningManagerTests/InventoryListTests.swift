import Foundation
import SwiftData
import Testing

@testable import SeasoningManager

@MainActor
struct InventoryListTests {
    @Test func inventoryKeepsEachCurrentItemAndExcludesConsumedAndUnknownStatuses() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: "しょうゆ", type: "調味料")
        let unopened = Item(product: product)
        let secondUnopened = Item(product: product)
        let inUse = Item(product: product, status: .inUse)
        let consumed = Item(product: product, status: .consumed)
        let unknown = Item(product: product)
        unknown.setValue(forKey: \.statusRawValue, to: "futureStatus")
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
        let product = try Product(name: "みそ", type: "調味料")
        context.insert(product)
        for rawValue in rawValues {
            let item = Item(product: product)
            item.setValue(forKey: \.statusRawValue, to: rawValue)
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
        let product = try Product(name: "しょうゆ", type: "調味料")
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

    @Test func rowsForTheSameProductKeepTheirOwnExpiration() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: " しょうゆ ", type: " 調味料 ")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dated = Item(product: product, expirationDate: date, status: .inUse)
        let undated = Item(product: product)
        context.insert(product)
        context.insert(dated)
        context.insert(undated)
        try context.save()

        let datedRow = InventoryItemRow(item: dated, status: .inUse)
        let undatedRow = InventoryItemRow(item: undated, status: .unopened)
        #expect(datedRow.productLabels.name == "しょうゆ")
        #expect(datedRow.productLabels.type == "調味料")
        let expectedDate = date.formatted(date: .abbreviated, time: .omitted)
        #expect(datedRow.expirationText == "賞味期限: \(expectedDate)")
        #expect(undatedRow.expirationText == "期限未設定")
    }

    @Test func detailLooksUpEachItemIDForSameProduct() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: " しょうゆ ", type: " 調味料 ")
        let opening = Date(timeIntervalSince1970: 1_700_000_000)
        let expiration = Date(timeIntervalSince1970: 1_710_000_000)
        let unopened = Item(product: product)
        let inUse = Item(product: product, expirationDate: expiration, status: .inUse, openingDate: opening)
        context.insert(product)
        context.insert(unopened)
        context.insert(inUse)
        try context.save()

        let reader = ModelContext(container)
        let unopenedMatches = try reader.fetch(ItemDetailView.descriptor(for: unopened.id))
        let inUseMatches = try reader.fetch(ItemDetailView.descriptor(for: inUse.id))
        #expect(unopenedMatches.map(\.id) == [unopened.id])
        #expect(inUseMatches.map(\.id) == [inUse.id])

        let unopenedDetail = try #require(ItemDetailContent(candidates: unopenedMatches))
        #expect(unopenedDetail.status == "未開封")
        #expect(unopenedDetail.expiration == "期限未設定")
        #expect(unopenedDetail.opening == "未設定")

        let inUseDetail = try #require(ItemDetailContent(candidates: inUseMatches))
        #expect(inUseDetail.product.name == "しょうゆ")
        #expect(inUseDetail.product.type == "調味料")
        #expect(inUseDetail.status == "使用中")
        #expect(inUseDetail.expiration == expiration.formatted(date: .abbreviated, time: .omitted))
        #expect(inUseDetail.opening == opening.formatted(date: .abbreviated, time: .omitted))
        #expect(!reader.hasChanges)
    }

    @Test func deletedItemHasNoDetailBeforeAndAfterSavingDeletion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try Product(name: "しょうゆ", type: "調味料")
        let item = Item(product: product)
        let itemID = item.id
        context.insert(product)
        context.insert(item)
        try context.save()

        let descriptor = ItemDetailView.descriptor(for: itemID)
        let candidates = try context.fetch(descriptor)
        let candidate = try #require(candidates.first)
        #expect(ItemDetailContent(candidates: candidates) != nil)

        context.delete(candidate)

        // 再照会まで古い候補が残っていても、削除された個体の属性には触れない。
        #expect(ItemDetailContent(candidates: candidates) == nil)
        try context.save()

        #expect(ItemDetailContent(candidates: candidates) == nil)
        let savedCandidates = try ModelContext(container).fetch(descriptor)
        #expect(savedCandidates.isEmpty)
        #expect(ItemDetailContent(candidates: savedCandidates) == nil)
    }

    @Test func duplicateItemIDHasNoDetail() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: "しょうゆ", type: "調味料")
        let itemID = UUID()
        context.insert(product)
        context.insert(Item(id: itemID, product: product))
        context.insert(Item(id: itemID, product: product))
        try context.save()

        let reader = ModelContext(container)
        let matches = try reader.fetch(ItemDetailView.descriptor(for: itemID))
        #expect(matches.count == 2)
        #expect(ItemDetailContent(candidates: matches) == nil)
        #expect(!reader.hasChanges)
    }

    @Test func blankFieldsAndUnavailableProductHaveDistinctLabels() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: " \t", type: "　\n")
        let item = Item(product: product)
        context.insert(product)
        context.insert(item)
        try context.save()

        let row = InventoryItemRow(item: item, status: .unopened)
        #expect(row.productLabels.name == "名前未設定")
        #expect(row.productLabels.type == "種類未設定")

        context.delete(product)
        #expect(row.productLabels.name == "商品情報なし")
        #expect(row.productLabels.type == "種類不明")
        #expect(ItemDetailContent(candidates: [item]) == nil)
    }

    @Test func missingProductRelationshipDoesNotHideCurrentItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: "しょうゆ", type: "調味料")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let item = Item(product: product, expirationDate: date)
        context.insert(product)
        context.insert(item)
        item.setValue(forKey: \.product, to: nil)
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(InventoryListView.descriptor())
        #expect(items.map(\.id) == [item.id])
        let saved = try #require(items.first)
        #expect(saved.product == nil)
        let row = InventoryItemRow(item: saved, status: .unopened)
        #expect(row.productLabels.name == "商品情報なし")
        #expect(row.productLabels.type == "種類不明")
        let expectedDate = date.formatted(date: .abbreviated, time: .omitted)
        #expect(row.expirationText == "賞味期限: \(expectedDate)")
        let candidates = try reader.fetch(ItemDetailView.descriptor(for: item.id))
        #expect(candidates.map(\.id) == [item.id])
        #expect(ItemDetailContent(candidates: candidates) == nil)
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
