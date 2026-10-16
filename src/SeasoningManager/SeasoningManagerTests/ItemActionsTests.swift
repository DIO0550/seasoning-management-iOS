import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ItemActionsTests {
    private let originalDate = Date(timeIntervalSince1970: 1_600_000_000)
    private let registrationDate = Date(timeIntervalSince1970: 1_750_000_123)
    private let expirationDate = Date(timeIntervalSince1970: 1_800_000_321)
    private let originalImage = Data([0, 1, 2, 255])

    nonisolated private enum StoreError: Error, Equatable {
        case unavailable
    }

    @Test(arguments: [nil, Date(timeIntervalSince1970: 1_700_000_123), Date(timeIntervalSince1970: 1_800_000_321)])
    func registrationPreservesOptionalPastAndFutureExpirationDates(_ expiration: Date?) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)

        let item = try ItemActions(context: context).create(
            for: product, expirationDate: expiration, now: registrationDate
        ).get()

        #expect(item.id != product.id)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectNewValues(item, expiration: expiration)
        expectProductValues(product)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1)

        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Item>()).first)
        #expect(saved.id == item.id)
        #expect(saved.product?.id == product.id)
        expectNewValues(saved, expiration: expiration)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 1)
    }

    @Test func repeatedRegistrationCreatesOneDistinctItemPerSaveAndPreservesExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let existing = makeExistingItem(product: product)
        context.insert(existing)
        try context.save()
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        let first = try actions.create(for: product, now: registrationDate).get()

        #expect(saveCalls == 1)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 2)
        #expect(first.id != existing.id)
        #expect(first.product === product)
        expectNewValues(first, expiration: nil)

        let second = try actions.create(
            for: product, expirationDate: expirationDate, now: registrationDate
        ).get()

        #expect(saveCalls == 2)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 3)
        #expect(Set([existing.id, first.id, second.id]).count == 3)
        #expect(second.product === product)
        expectNewValues(second, expiration: expirationDate)
        expectExistingValues(existing)
        #expect(existing.product === product)
        #expect(Set((product.items ?? []).map(\.id)) == Set([existing.id, first.id, second.id]))
        expectProductValues(product)
        expectProductValues(other, name: "みそ")
        #expect((other.items ?? []).isEmpty)
        #expect(!context.hasChanges)

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        let savedProduct = try #require(products.first { $0.id == product.id })
        let savedOther = try #require(products.first { $0.id == other.id })
        expectProductValues(savedProduct)
        expectProductValues(savedOther, name: "みそ")
        #expect((savedOther.items ?? []).isEmpty)
        #expect(Set((savedProduct.items ?? []).map(\.id)) == Set([existing.id, first.id, second.id]))
        let savedItems = try reader.fetch(FetchDescriptor<Item>())
        #expect(savedItems.count == 3)
        expectExistingValues(try #require(savedItems.first { $0.id == existing.id }))
    }

    @Test func registrationSurvivesReopeningStoreWithProductRelationship() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("items.store")
        var productID: UUID?
        var itemID: UUID?

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try makeSavedProduct(in: context)
            let item = try ItemActions(context: context).create(
                for: product, expirationDate: expirationDate, now: registrationDate
            ).get()
            productID = product.id
            itemID = item.id
            #expect(!context.hasChanges)
        }

        let reopened = try makeContainer(at: url)
        let reader = ModelContext(reopened)
        let products = try reader.fetch(FetchDescriptor<Product>())
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(products.count == 1)
        #expect(items.count == 1)
        let product = try #require(products.first)
        let item = try #require(items.first)
        #expect(product.id == productID)
        #expect(item.id == itemID)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectProductValues(product)
        expectNewValues(item, expiration: expirationDate)
    }

    @Test func unmanagedAndOtherContextProductsAreRejectedWithoutSaving() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let owner = ModelContext(container)
        let saved = try makeSavedProduct(in: owner)
        let unmanaged = Product(name: "未登録", type: "調味料", updatedAt: originalDate)
        let unmanagedID = unmanaged.id
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.productNotInContext) = actions.create(for: unmanaged) else {
            Issue.record("未管理の商品が拒否されなかった")
            return
        }
        guard case .failure(.productNotInContext) = actions.create(for: saved) else {
            Issue.record("別contextの商品が拒否されなかった")
            return
        }

        #expect(saveCalls == 0)
        #expect(unmanaged.id == unmanagedID)
        #expect(unmanaged.name == "未登録")
        #expect(unmanaged.type == "調味料")
        #expect(unmanaged.updatedAt == originalDate)
        #expect(unmanaged.modelContext == nil)
        #expect((unmanaged.items ?? []).isEmpty)
        expectProductValues(saved)
        #expect(saved.modelContext === owner)
        #expect((saved.items ?? []).isEmpty)
        #expect(!context.hasChanges)
        #expect(!owner.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<Product>()) == 1)
        expectProductValues(try #require(reader.fetch(FetchDescriptor<Product>()).first))
    }

    @Test func unsavedProductIsRejectedWithoutSavingOrRollingBackInput() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let pending = Product(name: "未保存", type: "調味料", updatedAt: originalDate)
        let productID = pending.id
        context.insert(pending)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.pendingChanges) = actions.create(for: pending) else {
            Issue.record("未保存の商品が拒否されなかった")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        #expect(pending.modelContext === context)
        #expect(pending.id == productID)
        #expect(pending.name == "未保存")
        #expect(pending.type == "調味料")
        #expect(pending.updatedAt == originalDate)
        #expect((pending.items ?? []).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<Product>()) == 0)
    }

    @Test func unrelatedPendingEditsAreNeitherSavedNorRolledBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        other.name = "編集中のみそ"
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.pendingChanges) = actions.create(for: product) else {
            Issue.record("無関係な未保存変更があるcontextで登録された")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        expectProductValues(product)
        expectProductValues(other, name: "編集中のみそ")
        #expect((product.items ?? []).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        expectProductValues(try #require(products.first { $0.id == product.id }))
        expectProductValues(try #require(products.first { $0.id == other.id }), name: "みそ")
    }

    @Test func failedRegistrationRestoresRelationshipsAndRetryCreatesOnlyOneItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let productID = product.id
        let existing = makeExistingItem(product: product)
        let existingID = existing.id
        context.insert(existing)
        try context.save()
        var saveCalls = 0
        let failing = ItemActions(context: context) { _ in
            saveCalls += 1
            return .failure(StoreError.unavailable)
        }

        let result = failing.create(for: product, expirationDate: expirationDate, now: registrationDate)

        guard case .failure(.persistence(let error)) = result else {
            Issue.record("元の保存エラーが返されなかった")
            return
        }
        #expect(error as? StoreError == .unavailable)
        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        #expect(product.id == productID)
        expectProductValues(product)
        #expect(existing.id == existingID)
        #expect(existing.product === product)
        expectExistingValues(existing)
        #expect(product.items?.map(\.id) == [existingID])
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1)

        do {
            let reader = ModelContext(container)
            let savedProduct = try #require(reader.fetch(FetchDescriptor<Product>()).first)
            let savedItems = try reader.fetch(FetchDescriptor<Item>())
            #expect(savedProduct.id == productID)
            expectProductValues(savedProduct)
            #expect(savedItems.count == 1)
            let savedItem = try #require(savedItems.first)
            #expect(savedItem.id == existingID)
            #expect(savedItem.product === savedProduct)
            #expect(savedProduct.items?.map(\.id) == [existingID])
            expectExistingValues(savedItem)
        }

        // 同じ商品と入力をそのまま再試行しても、失敗時の個体は重複しない。
        let retried = try ItemActions(context: context).create(
            for: product, expirationDate: expirationDate, now: registrationDate
        ).get()

        #expect(retried.product === product)
        #expect(retried.id != existingID)
        expectNewValues(retried, expiration: expirationDate)
        #expect(!context.hasChanges)
        #expect(Set((product.items ?? []).map(\.id)) == Set([existingID, retried.id]))
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 2)
        let reader = ModelContext(container)
        let savedItems = try reader.fetch(FetchDescriptor<Item>())
        #expect(savedItems.count == 2)
        let saved = try #require(savedItems.first { $0.id == retried.id })
        #expect(saved.product?.id == productID)
        expectNewValues(saved, expiration: expirationDate)
        expectExistingValues(try #require(savedItems.first { $0.id == existingID }))
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        if let url {
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSavedProduct(in context: ModelContext, name: String = "しょうゆ") throws -> Product {
        let product = Product(name: name, type: "調味料", updatedAt: originalDate)
        product.image = originalImage
        product.priceYen = 398
        product.calories = 1234
        product.protein = 1
        product.fat = 120
        product.sugar = 2
        product.carbohydrates = 456
        product.nutrientBasisAmount = 1500
        product.nutrientBasisUnit = "mL"
        context.insert(product)
        try context.save()
        return product
    }

    private func makeExistingItem(product: Product) -> Item {
        Item(
            product: product, expirationDate: originalDate, status: .inUse,
            openingDate: originalDate, updatedAt: originalDate
        )
    }

    private func expectProductValues(_ product: Product, name: String = "しょうゆ") {
        #expect(product.name == name)
        #expect(product.type == "調味料")
        #expect(product.image == originalImage)
        #expect(product.priceYen == 398)
        #expect(product.calories == 1234)
        #expect(product.protein == 1)
        #expect(product.fat == 120)
        #expect(product.sugar == 2)
        #expect(product.carbohydrates == 456)
        #expect(product.nutrientBasisAmount == 1500)
        #expect(product.nutrientBasisUnit == "mL")
        #expect(product.updatedAt == originalDate)
    }

    private func expectNewValues(_ item: Item, expiration: Date?) {
        #expect(item.expirationDate == expiration)
        #expect(item.status == .unopened)
        #expect(item.statusRawValue == "unopened")
        #expect(item.openingDate == nil)
        #expect(item.consumedDate == nil)
        #expect(item.updatedAt == registrationDate)
    }

    private func expectExistingValues(_ item: Item) {
        #expect(item.expirationDate == originalDate)
        #expect(item.status == .inUse)
        #expect(item.openingDate == originalDate)
        #expect(item.consumedDate == nil)
        #expect(item.updatedAt == originalDate)
    }
}
