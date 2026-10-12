import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ProductActionsTests {
    private let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let editedDate = Date(timeIntervalSince1970: 1_700_000_100)
    private let originalImage = Data([0, 1, 2, 255])

    nonisolated private enum StoreError: Error, Equatable {
        case unavailable
    }

    @Test func registrationAndEditingSurviveReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("products.store")
        var productID: UUID?

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try ProductActions(context: context).create(
                from: populatedDraft(), image: originalImage, now: originalDate
            )
            productID = product.id
            expectOriginalValues(product)
            #expect(!context.hasChanges)
        }

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try #require(context.fetch(FetchDescriptor<Product>()).first)
            #expect(product.id == productID)
            expectOriginalValues(product)

            try ProductActions(context: context).update(
                product, from: ProductDraft(name: "新しい名前", type: "調味料"), image: nil, now: editedDate
            )
        }

        do {
            let container = try makeContainer(at: url)
            let reader = ModelContext(container)
            let products = try reader.fetch(FetchDescriptor<Product>())
            #expect(products.count == 1)
            let product = try #require(products.first)
            #expect(product.id == productID)
            #expect(product.name == "新しい名前")
            #expect(product.type == "調味料")
            #expect(product.updatedAt == editedDate)
            expectUnsetValues(product)
        }
    }

    @Test func sameNameCreatesDistinctProductsWithUnsetAndZeroValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let actions = ProductActions(context: context)
        let unset = try actions.create(from: ProductDraft(name: "しょうゆ", type: "調味料"), now: originalDate)
        let zero = try actions.create(
            from: ProductDraft(
                name: "しょうゆ", type: "調味料", priceYen: "0", fat: "0",
                nutrientBasisAmount: "100", nutrientBasisUnit: "g"
            ), now: originalDate
        )

        #expect(unset.id != zero.id)
        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        expectUnsetValues(try #require(products.first { $0.id == unset.id }))
        let savedZero = try #require(products.first { $0.id == zero.id })
        #expect(savedZero.name == "しょうゆ")
        #expect(savedZero.priceYen == 0)
        #expect(savedZero.fat == 0)
        #expect(savedZero.calories == nil)
        #expect(savedZero.protein == nil)
        #expect(savedZero.sugar == nil)
        #expect(savedZero.carbohydrates == nil)
        #expect(savedZero.nutrientBasisAmount == 10000)
        #expect(savedZero.nutrientBasisUnit == "g")
    }

    @Test func editingRetainsIDAndItemRelationshipWithoutConvertingNutrients() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let actions = ProductActions(context: context)
        let product = try actions.create(from: populatedDraft(), image: originalImage, now: originalDate)
        let productID = product.id
        let item = Item(product: product, updatedAt: originalDate)
        context.insert(item)
        try context.save()
        let replacementImage = Data([10, 20, 30])
        var draft = populatedDraft()
        draft.name = "編集済み"
        draft.type = "新しい種類"
        draft.nutrientBasisAmount = "100"
        draft.nutrientBasisUnit = "g"

        try actions.update(product, from: draft, image: replacementImage, now: editedDate)

        #expect(product.id == productID)
        #expect(product.name == "編集済み")
        #expect(product.type == "新しい種類")
        #expect(product.image == replacementImage)
        #expect(product.updatedAt == editedDate)
        #expect(product.calories == 1234)
        #expect(product.protein == 1)
        #expect(product.fat == 120)
        #expect(product.sugar == 2)
        #expect(product.carbohydrates == 456)
        #expect(product.nutrientBasisAmount == 10000)
        #expect(product.nutrientBasisUnit == "g")
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])

        let reader = ModelContext(container)
        let savedItem = try #require(reader.fetch(FetchDescriptor<Item>()).first)
        #expect(savedItem.id == item.id)
        #expect(savedItem.product?.id == productID)
        #expect(savedItem.product?.image == replacementImage)
    }

    @Test func invalidInputDoesNotInsertOrPartiallyEdit() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let actions = ProductActions(context: context)
        let product = try actions.create(from: populatedDraft(), image: originalImage, now: originalDate)
        var draft = populatedDraft()
        draft.name = "変更してはいけない"
        draft.carbohydrates = "NaN"
        let expectedError = ProductDraft.ValidationError(field: .carbohydrates, reason: .invalidFormat)

        #expect(throws: expectedError) {
            _ = try actions.create(from: draft, image: nil, now: editedDate)
        }
        #expect(throws: expectedError) {
            try actions.update(product, from: draft, image: nil, now: editedDate)
        }

        expectOriginalValues(product)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        #expect(draft.name == "変更してはいけない")
        #expect(draft.carbohydrates == "NaN")
    }

    @Test func editingReplacesEveryNumericValueInStore() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let actions = ProductActions(context: context)
        let product = try actions.create(from: populatedDraft(), now: originalDate)
        let productID = product.id
        let draft = ProductDraft(
            name: "だし", type: "調味料", priceYen: "0", calories: "0", protein: "9.87",
            fat: "6.54", sugar: "3.21", carbohydrates: "1.23",
            nutrientBasisAmount: "1", nutrientBasisUnit: "食"
        )

        try actions.update(product, from: draft, image: nil, now: editedDate)

        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Product>()).first)
        #expect(saved.id == productID)
        #expect(saved.name == "だし")
        #expect(saved.type == "調味料")
        #expect(saved.priceYen == 0)
        #expect(saved.calories == 0)
        #expect(saved.protein == 987)
        #expect(saved.fat == 654)
        #expect(saved.sugar == 321)
        #expect(saved.carbohydrates == 123)
        #expect(saved.nutrientBasisAmount == 100)
        #expect(saved.nutrientBasisUnit == "食")
        #expect(saved.updatedAt == editedDate)
        #expect(!context.hasChanges)
    }

    @Test func failedRegistrationPreservesInputAndRetryCreatesOneProduct() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let draft = populatedDraft()
        let failing = ProductActions(context: context, save: { _ in throw StoreError.unavailable })

        #expect(throws: StoreError.unavailable) {
            _ = try failing.create(from: draft, image: originalImage, now: originalDate)
        }

        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(draft.name == "　だし しょうゆ\n")
        #expect(draft.carbohydrates == "4.56")

        let product = try ProductActions(context: context).create(
            from: draft, image: originalImage, now: originalDate
        )
        expectOriginalValues(product)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 1)
    }

    @Test func failedEditingRestoresOriginalProductAndRelationshipsBeforeRetry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let actions = ProductActions(context: context)
        let product = try actions.create(from: populatedDraft(), image: originalImage, now: originalDate)
        let productID = product.id
        let item = Item(product: product, updatedAt: originalDate)
        context.insert(item)
        try context.save()
        let draft = ProductDraft(name: "編集後", type: "編集後の種類")
        let failing = ProductActions(context: context, save: { _ in throw StoreError.unavailable })

        #expect(throws: StoreError.unavailable) {
            try failing.update(product, from: draft, image: nil, now: editedDate)
        }

        expectOriginalValues(product)
        #expect(product.id == productID)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        #expect(!context.hasChanges)
        do {
            let reader = ModelContext(container)
            let saved = try #require(reader.fetch(FetchDescriptor<Product>()).first)
            expectOriginalValues(saved)
        }
        #expect(draft.name == "編集後")
        #expect(draft.type == "編集後の種類")

        try actions.update(product, from: draft, image: nil, now: editedDate)
        #expect(product.id == productID)
        #expect(product.name == "編集後")
        #expect(product.updatedAt == editedDate)
        expectUnsetValues(product)
        #expect(item.product === product)
        let reader = ModelContext(container)
        let retried = try #require(reader.fetch(FetchDescriptor<Product>()).first)
        #expect(retried.name == "編集後")
        #expect(retried.updatedAt == editedDate)
        expectUnsetValues(retried)
    }

    @Test func pendingChangesAreNeitherSavedNorRolledBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let actions = ProductActions(context: context)
        let product = try actions.create(from: populatedDraft(), image: originalImage, now: originalDate)
        let pending = Product(name: "未保存", type: "調味料")
        context.insert(pending)
        let draft = ProductDraft(name: "別の商品", type: "調味料")

        #expect(throws: ProductActions.SaveError.pendingChanges) {
            _ = try actions.create(from: draft)
        }
        #expect(throws: ProductActions.SaveError.pendingChanges) {
            try actions.update(product, from: draft, image: nil, now: editedDate)
        }

        expectOriginalValues(product)
        #expect(context.hasChanges)
        #expect(pending.modelContext === context)
        #expect(pending.name == "未保存")
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 1)
    }

    @Test func editingRejectsUnmanagedAndOtherContextProducts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let owner = ModelContext(container)
        let saved = try ProductActions(context: owner).create(
            from: populatedDraft(), image: originalImage, now: originalDate
        )
        let unmanaged = Product(name: "未登録", type: "調味料", updatedAt: originalDate)
        let actions = ProductActions(context: context)
        let draft = ProductDraft(name: "編集後", type: "調味料")

        #expect(throws: ProductActions.SaveError.productNotInContext) {
            try actions.update(unmanaged, from: draft, image: nil, now: editedDate)
        }
        #expect(throws: ProductActions.SaveError.productNotInContext) {
            try actions.update(saved, from: draft, image: nil, now: editedDate)
        }

        #expect(unmanaged.name == "未登録")
        #expect(unmanaged.updatedAt == originalDate)
        expectOriginalValues(saved)
        #expect(!context.hasChanges)
        #expect(!owner.hasChanges)
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

    private func populatedDraft() -> ProductDraft {
        ProductDraft(
            name: "　だし しょうゆ\n", type: "　和風 だし\t", priceYen: "398",
            calories: "12.34", protein: "0.01", fat: "1.2", sugar: "0.02", carbohydrates: "4.56",
            nutrientBasisAmount: "15", nutrientBasisUnit: " mL "
        )
    }

    private func expectOriginalValues(_ product: Product) {
        #expect(product.name == "だし しょうゆ")
        #expect(product.type == "和風 だし")
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

    private func expectUnsetValues(_ product: Product) {
        #expect(product.image == nil)
        #expect(product.priceYen == nil)
        #expect(product.calories == nil)
        #expect(product.protein == nil)
        #expect(product.fat == nil)
        #expect(product.sugar == nil)
        #expect(product.carbohydrates == nil)
        #expect(product.nutrientBasisAmount == nil)
        #expect(product.nutrientBasisUnit == nil)
    }
}
