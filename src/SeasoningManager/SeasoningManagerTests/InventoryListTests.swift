import Foundation
import SwiftData
import SwiftUI
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

        let datedRow = InventoryItemRow(item: dated, status: .inUse, now: date)
        let undatedRow = InventoryItemRow(item: undated, status: .unopened, now: date)
        #expect(datedRow.productLabels.name == "しょうゆ")
        #expect(datedRow.productLabels.type == "調味料")
        let expectedDate = date.formatted(date: .abbreviated, time: .omitted)
        #expect(datedRow.expirationPresentation().rowText == "賞味期限: \(expectedDate)（期限が近い）")
        #expect(undatedRow.expirationPresentation().rowText == "期限未設定")
    }

    @Test(
        arguments: [
            (-1 as Int?, "期限切れ" as String?, Color.red as Color?),
            (0, "期限が近い", .orange),
            (7, "期限が近い", .orange),
            (8, nil, nil),
            (nil, nil, nil),
        ],
        [ItemStatus.unopened, .inUse]
    )
    func expirationWarningsMatchInListAndDetail(
        _ sample: (daysFromToday: Int?, warning: String?, color: Color?), _ status: ItemStatus
    ) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10)))
        let tonight = try #require(calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now))
        let expirationDate = try sample.daysFromToday.map { days in
            try #require(calendar.date(byAdding: .day, value: days, to: tonight))
        }

        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: "しょうゆ", type: "調味料")
        let openingDate = status == .inUse ? now : nil
        let item = Item(product: product, expirationDate: expirationDate, status: status, openingDate: openingDate)
        context.insert(product)
        context.insert(item)
        try context.save()

        let row = InventoryItemRow(item: item, status: status, now: now)
        let detail = try ItemDetailContent.resolve(candidates: [item]).get()
        let rowExpiration = row.expirationPresentation(calendar: calendar)
        let detailExpiration = detail.expirationPresentation(now: now, calendar: calendar)

        let expectedRow: String
        let expectedDetail: String
        if let expirationDate {
            let dateStyle = Date.FormatStyle(
                date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone
            )
            let date = expirationDate.formatted(dateStyle)
            expectedDetail = sample.warning.map { "\(date)（\($0)）" } ?? date
            expectedRow = "賞味期限: \(expectedDetail)"
        } else {
            expectedDetail = "期限未設定"
            expectedRow = "期限未設定"
        }

        #expect(rowExpiration.rowText == expectedRow)
        #expect(detailExpiration.detailText == expectedDetail)
        #expect(rowExpiration.warningColor == sample.color)
        #expect(detailExpiration.warningColor == sample.color)
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

        let unopenedDetail = try ItemDetailContent.resolve(candidates: unopenedMatches).get()
        #expect(unopenedDetail.status == "未開封")
        #expect(unopenedDetail.expirationDate == nil)
        #expect(unopenedDetail.opening == "未設定")

        let inUseDetail = try ItemDetailContent.resolve(candidates: inUseMatches).get()
        #expect(inUseDetail.product.name == "しょうゆ")
        #expect(inUseDetail.product.type == "調味料")
        #expect(inUseDetail.status == "使用中")
        #expect(inUseDetail.expirationDate == expiration)
        #expect(inUseDetail.opening == opening.formatted(date: .abbreviated, time: .omitted))
        #expect(!reader.hasChanges)
    }

    @Test func insertedItemOnlyBecomesAvailableAfterSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try Product(name: "しょうゆ", type: "調味料")
        context.insert(product)
        try context.save()

        let item = Item(product: product)
        let descriptor = ItemDetailView.descriptor(for: item.id)
        context.insert(item)
        #expect(try context.fetch(descriptor).isEmpty)

        try context.save()
        let matches = try context.fetch(descriptor)
        #expect(matches.map(\.id) == [item.id])
        let detail = try ItemDetailContent.resolve(candidates: matches).get()
        #expect(detail.status == "未開封")
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
        let detail = try ItemDetailContent.resolve(candidates: candidates).get()
        #expect(detail.status == "未開封")

        context.delete(candidate)

        // 再照会まで古い候補が残っていても、削除された個体の属性には触れない。
        #expect(throws: ItemDetailContent.Unavailable.notFound) {
            try ItemDetailContent.resolve(candidates: candidates).get()
        }
        try context.save()

        #expect(throws: ItemDetailContent.Unavailable.notFound) {
            try ItemDetailContent.resolve(candidates: candidates).get()
        }
        let savedCandidates = try ModelContext(container).fetch(descriptor)
        #expect(savedCandidates.isEmpty)
        #expect(throws: ItemDetailContent.Unavailable.notFound) {
            try ItemDetailContent.resolve(candidates: savedCandidates).get()
        }
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
        #expect(throws: ItemDetailContent.Unavailable.duplicateID) {
            try ItemDetailContent.resolve(candidates: matches).get()
        }
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

        let row = InventoryItemRow(item: item, status: .unopened, now: item.updatedAt)
        #expect(row.productLabels.name == "名前未設定")
        #expect(row.productLabels.type == "種類未設定")

        context.delete(product)
        let deletedProductLabels = InventoryProductLabels(product: product)
        #expect(deletedProductLabels.name == "商品情報なし")
        #expect(deletedProductLabels.type == "種類不明")
        #expect(row.productLabels.name == "商品情報なし")
        #expect(row.productLabels.type == "種類不明")

        let detail = try ItemDetailContent.resolve(candidates: [item]).get()
        #expect(detail.product.name == "商品情報なし")
        #expect(detail.product.type == "種類不明")
        #expect(detail.status == "未開封")
    }

    @Test func missingProductRelationshipDoesNotHideCurrentItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try Product(name: "しょうゆ", type: "調味料")
        let opening = Date(timeIntervalSince1970: 1_700_000_000)
        let expiration = Date(timeIntervalSince1970: 1_710_000_000)
        let item = Item(product: product, expirationDate: expiration, status: .inUse, openingDate: opening)
        context.insert(product)
        context.insert(item)
        item.setValue(forKey: \.product, to: nil)
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(InventoryListView.descriptor())
        #expect(items.map(\.id) == [item.id])
        let saved = try #require(items.first)
        #expect(saved.product == nil)
        let row = InventoryItemRow(item: saved, status: .inUse, now: opening)
        #expect(row.productLabels.name == "商品情報なし")
        #expect(row.productLabels.type == "種類不明")
        let expectedExpiration = expiration.formatted(date: .abbreviated, time: .omitted)
        #expect(row.expirationPresentation().rowText == "賞味期限: \(expectedExpiration)")

        let candidates = try reader.fetch(ItemDetailView.descriptor(for: item.id))
        #expect(candidates.map(\.id) == [item.id])
        let detail = try ItemDetailContent.resolve(candidates: candidates).get()
        #expect(detail.product.name == "商品情報なし")
        #expect(detail.product.type == "種類不明")
        #expect(detail.status == "使用中")
        #expect(detail.expirationPresentation(now: opening).detailText == expectedExpiration)
        #expect(detail.opening == opening.formatted(date: .abbreviated, time: .omitted))
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
