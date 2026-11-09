import Foundation
import SwiftData
import Testing

@testable import SeasoningManager

@MainActor
struct ItemFormStateTests {
    private let expiration = Date(timeIntervalSince1970: 1_700_000_000)

    nonisolated private enum StoreError: LocalizedError, Equatable {
        case unavailable

        var errorDescription: String? {
            "保存先を利用できません。"
        }
    }

    @Test func discardingInputDoesNotCreateAnItemOrChangeProduct() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)

        do {
            var state = ItemFormState()
            state.selectedProductID = product.id
            state.hasExpirationDate = true
            state.expirationDate = expiration
            #expect(state.selectedProduct(in: [product]) === product)
            #expect(!context.hasChanges)
        }

        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        let saved = try #require(reader.fetch(FetchDescriptor<Product>()).first)
        #expect(saved.name == "しょうゆ")
        #expect(saved.type == "調味料")
        #expect(!context.hasChanges)
    }

    @Test(arguments: [false, true])
    func savingCreatesOneUnopenedItemForSelectedProduct(_ hasExpiration: Bool) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = try makeSavedProduct(in: context)
        let selected = try makeSavedProduct(in: context)
        var state = ItemFormState()
        state.selectedProductID = selected.id
        state.hasExpirationDate = hasExpiration
        state.expirationDate = expiration

        let itemID = try state.save(products: [first, selected], using: ItemActions(context: context)).get()

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.id == itemID)
        #expect(item.product?.id == selected.id)
        #expect(item.status == .unopened)
        #expect(item.openingDate == nil)
        #expect(item.consumedDate == nil)
        #expect(item.expirationDate == (hasExpiration ? expiration : nil))
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        let savedFirst = try #require(products.first { $0.id == first.id })
        #expect((savedFirst.items ?? []).isEmpty)
        #expect(state.savedItemID == itemID)
        #expect(state.error == nil)
        #expect(!context.hasChanges)
    }

    @Test func turningExpirationOffSavesNoDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ItemFormState()
        state.selectedProductID = product.id
        state.hasExpirationDate = true
        state.expirationDate = expiration
        state.hasExpirationDate = false

        _ = try state.save(products: [product], using: ItemActions(context: context)).get()

        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Item>()).first)
        #expect(saved.expirationDate == nil)
    }

    @Test func repeatedSaveCreatesOneItemAndNewFormCanAddAnother() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }
        var state = ItemFormState()
        state.selectedProductID = product.id

        let firstID = try state.save(products: [product], using: actions).get()
        let repeatedID = try state.save(products: [product], using: actions).get()
        #expect(firstID == repeatedID)
        #expect(saveCalls == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Item>()) == 1)

        var next = ItemFormState()
        next.selectedProductID = product.id
        let nextID = try next.save(products: [product], using: actions).get()
        #expect(nextID != firstID)
        #expect(saveCalls == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Item>()) == 2)
    }

    @Test func failurePreservesInputAndRetryCreatesOnlyOneItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ItemFormState()
        state.selectedProductID = product.id
        state.hasExpirationDate = true
        state.expirationDate = expiration
        let failing = ItemActions(context: context) { _ in
            .failure(StoreError.unavailable)
        }

        guard case .failure(.persistence(let error)) = state.save(products: [product], using: failing) else {
            Issue.record("保存失敗が呼び出し元へ返されなかった")
            return
        }
        #expect(error as? StoreError == .unavailable)
        #expect(state.selectedProductID == product.id)
        #expect(state.hasExpirationDate)
        #expect(state.expirationDate == expiration)
        #expect(state.savedItemID == nil)
        #expect(state.saveErrorMessage?.contains("保存先を利用できません。") == true)
        #expect(!context.hasChanges)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Item>()) == 0)

        let itemID = try state.save(products: [product], using: ItemActions(context: context)).get()

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(items.first?.id == itemID)
        #expect(items.first?.expirationDate == expiration)
        #expect(state.error == nil)
        #expect(state.saveErrorMessage == nil)
    }

    @Test func missingSelectionDoesNotSaveAndCanBeCorrected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ItemFormState()
        let actions = ItemActions(context: context)

        guard case .failure(.productNotInContext) = state.save(products: [product], using: actions) else {
            Issue.record("商品未選択の保存が拒否されなかった")
            return
        }
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(state.saveErrorMessage != nil)

        state.selectedProductID = product.id
        _ = try state.save(products: [product], using: actions).get()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Item>()) == 1)
        #expect(state.error == nil)
    }

    @Test(arguments: [false, true])
    func unavailableSelectedProductDoesNotSave(_ deleted: Bool) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ItemFormState()
        state.selectedProductID = product.id
        let candidates: [Product]
        if deleted {
            context.delete(product)
            candidates = [product]
        } else {
            candidates = []
        }

        let result = state.save(products: candidates, using: ItemActions(context: context))

        guard case .failure(.productNotInContext) = result else {
            Issue.record("利用できない商品への保存が拒否されなかった")
            return
        }
        #expect(state.selectedProduct(in: candidates) == nil)
        #expect(state.savedItemID == nil)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Item>()) == 0)
    }

    @Test func productFromAnotherContextDoesNotSave() throws {
        let container = try makeContainer()
        let owner = ModelContext(container)
        let product = try makeSavedProduct(in: owner)
        let context = ModelContext(container)
        var state = ItemFormState()
        state.selectedProductID = product.id

        let result = state.save(products: [product], using: ItemActions(context: context))

        guard case .failure(.productNotInContext) = result else {
            Issue.record("別contextの商品への保存が拒否されなかった")
            return
        }
        #expect(!owner.hasChanges)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(state.savedItemID == nil)
    }

    @Test func pendingChangesAreNeitherSavedNorDiscarded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let pending = try Product(name: "保存前の商品", type: "調味料")
        context.insert(pending)
        var state = ItemFormState()
        state.selectedProductID = product.id
        state.hasExpirationDate = true
        state.expirationDate = expiration

        let result = state.save(products: [product], using: ItemActions(context: context))

        guard case .failure(.pendingChanges) = result else {
            Issue.record("未保存変更があるcontextへの登録が拒否されなかった")
            return
        }
        #expect(context.hasChanges)
        #expect(pending.modelContext === context)
        #expect(state.selectedProductID == product.id)
        #expect(state.expirationDate == expiration)
        #expect(state.savedItemID == nil)
        #expect(state.saveErrorMessage != nil)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<Product>()) == 1)
    }

    private func makeSavedProduct(in context: ModelContext) throws -> Product {
        let product = try Product(name: "しょうゆ", type: "調味料")
        context.insert(product)
        try context.save()
        return product
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
