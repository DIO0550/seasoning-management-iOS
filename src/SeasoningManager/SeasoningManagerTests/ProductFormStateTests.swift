import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ProductFormStateTests {
    nonisolated private enum StoreError: LocalizedError, Equatable {
        case unavailable

        var errorDescription: String? {
            "保存先を利用できません。"
        }
    }

    @Test func enteringDraftDoesNotChangeContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var state = ProductFormState()

        state.draft.name = "　登録前の商品 "
        state.draft.type = "　しょうゆ "

        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(state.error == nil)
    }

    @Test(arguments: ["", " \t\n", "　", "\u{00a0}\u{2003}\u{2028}"])
    func blankNameRemainsInFormWithoutSaving(_ input: String) throws {
        try expectRejectedDraft(ProductDraft(name: input, type: "しょうゆ"), field: .name)
    }

    @Test(arguments: ["", " \t\n", "　", "\u{00a0}\u{2003}\u{2028}"])
    func blankTypeRemainsInFormWithoutSaving(_ input: String) throws {
        try expectRejectedDraft(ProductDraft(name: "丸大豆しょうゆ", type: input), field: .type)
    }

    @Test func savingCreatesOneNormalizedProduct() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var state = ProductFormState()
        state.draft.name = "　丸大豆 しょうゆ\n"
        state.draft.type = "\u{2003}和風 調味料\t"

        let saveSucceeded = state.save(using: ProductActions(context: context))
        #expect(saveSucceeded)

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.name == "丸大豆 しょうゆ")
        #expect(product.type == "和風 調味料")
        #expect(!context.hasChanges)
        #expect(state.error == nil)
    }

    @Test func persistenceFailurePreservesDraftAndRetryClearsError() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var state = ProductFormState()
        state.draft.name = "　再試行する商品 "
        state.draft.type = " しょうゆ\t"
        let failing = ProductActions(context: context) { _ in
            .failure(StoreError.unavailable)
        }

        let firstSaveSucceeded = state.save(using: failing)
        #expect(!firstSaveSucceeded)

        guard case .persistence(let underlying) = state.error else {
            Issue.record("保存失敗が画面の状態に保持されなかった")
            return
        }
        #expect(underlying as? StoreError == .unavailable)
        #expect(state.saveErrorMessage?.contains("保存先を利用できません。") == true)
        #expect(state.draft.name == "　再試行する商品 ")
        #expect(state.draft.type == " しょうゆ\t")
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 0)

        // 同じ入力状態から保存し直しても、失敗した商品の重複は作らない。
        let retrySucceeded = state.save(using: ProductActions(context: context))
        #expect(retrySucceeded)

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        #expect(products.first?.name == "再試行する商品")
        #expect(products.first?.type == "しょうゆ")
        #expect(state.error == nil)
        #expect(state.saveErrorMessage == nil)
    }

    @Test func unrelatedUnsavedChangesSurviveInputAndRejectedSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let existing = Product(name: "元の商品", type: "みそ")
        context.insert(existing)
        try context.save()
        existing.name = "ほかの画面で編集中"
        var saveCalls = 0
        let actions = ProductActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }
        var state = ProductFormState()
        state.draft.name = " 新しい商品 "
        state.draft.type = " しょうゆ "

        #expect(existing.name == "ほかの画面で編集中")
        #expect(context.hasChanges)
        let saveSucceeded = state.save(using: actions)
        #expect(!saveSucceeded)

        guard case .pendingChanges = state.error else {
            Issue.record("共有contextの未保存変更が検出されなかった")
            return
        }
        #expect(saveCalls == 0)
        #expect(existing.name == "ほかの画面で編集中")
        #expect(context.hasChanges)
        #expect(state.draft.name == " 新しい商品 ")
        #expect(state.draft.type == " しょうゆ ")
        #expect(state.saveErrorMessage != nil)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        let reader = ModelContext(container)
        let saved = try reader.fetch(FetchDescriptor<Product>())
        #expect(saved.count == 1)
        #expect(saved.first?.name == "元の商品")
    }

    private func expectRejectedDraft(_ draft: ProductDraft, field: ProductDraft.Field) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var saveCalls = 0
        let actions = ProductActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }
        var state = ProductFormState()
        state.draft = draft

        let saveSucceeded = state.save(using: actions)
        #expect(!saveSucceeded)

        guard case .validation(let error) = state.error else {
            Issue.record("必須項目のエラーが画面の状態に保持されなかった")
            return
        }
        #expect(error == ProductDraft.ValidationError(field: field, reason: .required))
        #expect((state.validationMessage(for: .name) != nil) == (field == .name))
        #expect((state.validationMessage(for: .type) != nil) == (field == .type))
        #expect(state.saveErrorMessage == nil)
        #expect(state.draft.name == draft.name)
        #expect(state.draft.type == draft.type)
        #expect(saveCalls == 0)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
