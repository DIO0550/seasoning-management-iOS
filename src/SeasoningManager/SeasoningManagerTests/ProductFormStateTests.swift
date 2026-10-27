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
        #expect(state.savedProductID == nil)
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
        var saveCalls = 0
        let actions = ProductActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }
        var selectedIDs: [UUID] = []
        var state = ProductFormState()
        state.draft.name = "　丸大豆 しょうゆ\n"
        state.draft.type = "\u{2003}和風 調味料\t"

        let productID = try state.save(using: actions) { selectedIDs.append($0) }.get()

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(productID == product.id)
        #expect(selectedIDs == [product.id])
        #expect(saveCalls == 1)
        #expect(product.name == "丸大豆 しょうゆ")
        #expect(product.type == "和風 調味料")
        #expect(!context.hasChanges)
        #expect(state.error == nil)
        #expect(state.savedProductID == product.id)
    }

    @Test func repeatedSaveReturnsSameProductWithoutSavingOrNotifyingAgain() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var saveCalls = 0
        let actions = ProductActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }
        var selectedIDs: [UUID] = []
        var state = ProductFormState()
        state.draft = ProductDraft(name: "丸大豆しょうゆ", type: "しょうゆ")

        let firstID = try state.save(using: actions) { selectedIDs.append($0) }.get()
        let repeatedID = try state.save(using: actions) { selectedIDs.append($0) }.get()

        let products = try ModelContext(container).fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(firstID == product.id)
        #expect(repeatedID == product.id)
        #expect(selectedIDs == [product.id])
        #expect(saveCalls == 1)
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
        var selectedIDs: [UUID] = []

        let firstResult = state.save(using: failing) { selectedIDs.append($0) }
        guard case .failure(.persistence(let returnedError)) = firstResult else {
            Issue.record("保存失敗が呼び出し元へ返されなかった")
            return
        }
        #expect(returnedError as? StoreError == .unavailable)
        #expect(selectedIDs.isEmpty)
        #expect(state.savedProductID == nil)

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
        let productID = try state.save(using: ProductActions(context: context)) { selectedIDs.append($0) }.get()

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(productID == product.id)
        #expect(selectedIDs == [product.id])
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
        var selectedIDs: [UUID] = []

        #expect(existing.name == "ほかの画面で編集中")
        #expect(context.hasChanges)
        let result = state.save(using: actions) { selectedIDs.append($0) }
        guard case .failure(.pendingChanges) = result else {
            Issue.record("共有contextの未保存変更が呼び出し元へ返されなかった")
            return
        }
        #expect(selectedIDs.isEmpty)
        #expect(state.savedProductID == nil)

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

    @Test func editingDraftStartsWithSavedValuesWithoutChangingProduct() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)

        #expect(state.isEditing)
        #expect(state.draft.name == "元の商品")
        #expect(state.draft.type == "しょうゆ")
        expectOriginalOptionalDraft(state.draft)
        state.draft.priceYen = "398"
        state.draft.protein = "1.23"
        state.draft.name = "保存しない名前"
        state.draft.type = "保存しない種類"

        // フォームを破棄するまで入力だけを変え、保存済みモデルには触れない。
        #expect(product.name == "元の商品")
        #expect(product.type == "しょうゆ")
        #expect(!context.hasChanges)
        let reopened = ProductFormState(product: product)
        #expect(reopened.draft.name == "元の商品")
        #expect(reopened.draft.type == "しょうゆ")
        expectOriginalOptionalDraft(reopened.draft)
        expectOptionalValues(product)
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.name == "元の商品")
        #expect(saved.type == "しょうゆ")
    }

    @Test func editingUpdatesOnlyTargetAndPreservesOptionalValuesAndItems() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let other = Product(name: product.name, type: product.type)
        let item = Item(product: product)
        context.insert(other)
        context.insert(item)
        try context.save()
        let productID = product.id
        let otherID = other.id
        let itemID = item.id
        var state = ProductFormState(product: product)
        state.draft.name = "　編集後の商品 "
        state.draft.type = " みそ\n"
        var selectedIDs: [UUID] = []
        var saveCalls = 0
        let actions = ProductActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        let savedID = try state.save(using: actions) { selectedIDs.append($0) }.get()
        let repeatedID = try state.save(using: actions) { selectedIDs.append($0) }.get()

        #expect(savedID == productID)
        #expect(repeatedID == productID)
        #expect(selectedIDs == [productID])
        #expect(saveCalls == 1)
        #expect(state.savedProductID == productID)
        #expect(state.error == nil)
        #expect(product.updatedAt != Date(timeIntervalSince1970: 1))
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [itemID])
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        let saved = try #require(products.first { $0.id == productID })
        #expect(saved.name == "編集後の商品")
        #expect(saved.type == "みそ")
        expectOptionalValues(saved)
        let untouched = try #require(products.first { $0.id == otherID })
        #expect(untouched.name == "元の商品")
        #expect(untouched.type == "しょうゆ")
        let savedItem = try #require(reader.fetch(FetchDescriptor<Item>()).first)
        #expect(savedItem.id == itemID)
        #expect(savedItem.product?.id == productID)
    }

    @Test(arguments: [nil, Int64(0), Int64.max] as [Int64?])
    func editingPreservesUnsetZeroAndMaximumPrice(_ price: Int64?) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "元の商品", type: "しょうゆ")
        product.priceYen = price
        context.insert(product)
        try context.save()
        var state = ProductFormState(product: product)
        let expectedPrice = price.map { String($0) } ?? ""
        #expect(state.draft.priceYen == expectedPrice)
        state.draft.name = "編集後"

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.priceYen == price)
        #expect(saved.image == nil)
        #expect(saved.calories == nil)
        #expect(saved.protein == nil)
        #expect(saved.fat == nil)
        #expect(saved.sugar == nil)
        #expect(saved.carbohydrates == nil)
        #expect(saved.nutrientBasisAmount == nil)
        #expect(saved.nutrientBasisUnit == nil)
    }

    @Test func editingUsesDraftValuesAndCurrentImage() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        state.draft.name = "編集後"
        product.priceYen = 500
        product.image = Data([4, 5, 6])
        product.protein = 456
        try context.save()

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.name == "編集後")
        #expect(saved.priceYen == 0)
        #expect(saved.image == Data([4, 5, 6]))
        #expect(saved.protein == nil)
    }

    @Test func editingSaveFailureKeepsOriginalValuesAndDraftForRetry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let productID = product.id
        let item = Item(product: product)
        context.insert(item)
        try context.save()
        var state = ProductFormState(product: product)
        state.draft.name = " 編集後 "
        state.draft.type = " みそ "
        state.draft.priceYen = "398"
        state.draft.fat = "1.23"
        state.draft.sugar = "4.56"
        state.draft.nutrientBasisAmount = "100"
        state.draft.nutrientBasisUnit = "g"
        var selectedIDs: [UUID] = []
        let failing = ProductActions(context: context) { _ in .failure(StoreError.unavailable) }

        let result = state.save(using: failing) { selectedIDs.append($0) }

        guard case .failure(.persistence(let underlying)) = result else {
            Issue.record("編集の保存失敗が返されなかった")
            return
        }
        #expect(underlying as? StoreError == .unavailable)
        #expect(state.savedProductID == nil)
        #expect(selectedIDs.isEmpty)
        #expect(state.draft.name == " 編集後 ")
        #expect(state.draft.type == " みそ ")
        #expect(state.draft.priceYen == "398")
        #expect(state.draft.fat == "1.23")
        #expect(state.draft.sugar == "4.56")
        #expect(state.draft.nutrientBasisAmount == "100")
        #expect(state.draft.nutrientBasisUnit == "g")
        #expect(state.saveErrorMessage?.contains("保存先を利用できません。") == true)
        #expect(product.name == "元の商品")
        #expect(product.type == "しょうゆ")
        #expect(product.updatedAt == Date(timeIntervalSince1970: 1))
        #expect(item.product === product)
        expectOptionalValues(product)
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Product>()).first)
        #expect(saved.id == productID)
        #expect(saved.name == "元の商品")
        #expect(saved.type == "しょうゆ")
        expectOptionalValues(saved)
        #expect(try reader.fetch(FetchDescriptor<Item>()).first?.product?.id == productID)

        let retriedID = try state.save(using: ProductActions(context: context)) { selectedIDs.append($0) }.get()

        #expect(retriedID == productID)
        #expect(selectedIDs == [productID])
        #expect(state.error == nil)
        #expect(state.saveErrorMessage == nil)
        let retried = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(retried.id == productID)
        #expect(retried.name == "編集後")
        #expect(retried.type == "みそ")
        #expect(retried.image == Data([1, 2, 3]))
        #expect(retried.priceYen == 398)
        #expect(retried.fat == 123)
        #expect(retried.sugar == 456)
        #expect(retried.nutrientBasisAmount == 10000)
        #expect(retried.nutrientBasisUnit == "g")
        #expect(try ModelContext(container).fetch(FetchDescriptor<Item>()).first?.product?.id == productID)
    }

    @Test(arguments: [ProductDraft.Field.name, .type])
    func editingRejectsBlankRequiredFieldWithoutChangingProduct(_ field: ProductDraft.Field) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        state.draft = ProductDraft(name: "編集後", type: "みそ")
        switch field {
        case .name:
            state.draft.name = "　 "
        default:
            state.draft.type = "　 "
        }
        var notifications = 0

        let result = state.save(using: ProductActions(context: context)) { _ in notifications += 1 }

        guard case .failure(.validation(let validation)) = result else {
            Issue.record("編集の必須入力が拒否されなかった")
            return
        }
        #expect(validation.field == field)
        #expect(state.validationMessage(for: field) != nil)
        #expect(state.savedProductID == nil)
        #expect(notifications == 0)
        #expect(product.name == "元の商品")
        #expect(product.type == "しょうゆ")
        expectOptionalValues(product)
        #expect(!context.hasChanges)
    }

    @Test func editingRejectsPendingChangesWithoutRollingThemBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        state.draft.name = "編集後"
        product.priceYen = 500
        var notifications = 0

        let result = state.save(using: ProductActions(context: context)) { _ in notifications += 1 }

        guard case .failure(.pendingChanges) = result else {
            Issue.record("未保存の変更がある編集を拒否しなかった")
            return
        }
        #expect(notifications == 0)
        #expect(state.savedProductID == nil)
        #expect(state.draft.name == "編集後")
        #expect(state.saveErrorMessage != nil)
        #expect(product.name == "元の商品")
        #expect(product.priceYen == 500)
        #expect(context.hasChanges)
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.priceYen == 0)
        #expect(saved.name == "元の商品")
    }

    @Test func deletedProductCannotBeInitializedOrSavedAsAnEdit() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        var opened = ProductFormState(product: product)
        opened.draft.name = "編集後"
        context.delete(product)
        try context.save()
        var reopened = ProductFormState(product: product)
        var notifications = 0

        let results = [
            opened.save(using: ProductActions(context: context)) { _ in notifications += 1 },
            reopened.save(using: ProductActions(context: context)) { _ in notifications += 1 },
        ]

        for result in results {
            guard case .failure(.productNotInContext) = result else {
                Issue.record("削除済み商品の編集を拒否しなかった")
                return
            }
        }
        #expect(reopened.draft.name.isEmpty)
        #expect(reopened.draft.type.isEmpty)
        #expect(opened.draft.name == "編集後")
        #expect(opened.savedProductID == nil)
        #expect(reopened.savedProductID == nil)
        #expect(notifications == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 0)
    }

    @Test func editingShowsSavedInvalidValueInItsFieldAndAllowsCorrection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        product.priceYen = -1
        try context.save()
        var state = ProductFormState(product: product)
        state.draft.name = "編集後"

        let result = state.save(using: ProductActions(context: context)) { _ in
            Issue.record("不正な登録済みデータで保存成功を通知した")
        }

        guard case .failure(.validation(let validation)) = result else {
            Issue.record("不正な登録済み価格を拒否しなかった")
            return
        }
        #expect(validation.field == .priceYen)
        #expect(state.saveErrorMessage == nil)
        #expect(state.validationMessage(for: .priceYen)?.contains("0以上の半角整数") == true)
        #expect(state.draft.priceYen == "-1")
        #expect(state.draft.name == "編集後")
        #expect(product.name == "元の商品")
        #expect(product.priceYen == -1)
        #expect(!context.hasChanges)

        state.draft.priceYen = "398"
        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let corrected = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(corrected.priceYen == 398)
        #expect(state.validationMessage(for: .priceYen) == nil)
    }

    @Test(arguments: [false, true])
    func optionalInputsAreSavedAndRestoredWithoutRounding(_ editing: Bool) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product: Product?
        if editing {
            product = try makeSavedProduct(in: context)
        } else {
            product = nil
        }
        var state = ProductFormState(product: product)
        state.draft = ProductDraft(
            name: "商品", type: "種類", priceYen: "0", calories: "12.34", protein: "0", fat: "1.23",
            sugar: "4.56", carbohydrates: "92233720368547758.07",
            nutrientBasisAmount: "0.01", nutrientBasisUnit: "食"
        )

        let id = try state.save(using: ProductActions(context: context)) { _ in }.get()
        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Product>()).first)
        #expect(saved.id == id)
        #expect(saved.priceYen == 0)
        #expect(saved.calories == 1234)
        #expect(saved.protein == 0)
        #expect(saved.fat == 123)
        #expect(saved.sugar == 456)
        #expect(saved.carbohydrates == Int64.max)
        #expect(saved.nutrientBasisAmount == 1)
        #expect(saved.nutrientBasisUnit == "食")
        #expect(saved.image == product?.image)

        let reopened = ProductFormState(product: saved)
        #expect(reopened.draft.priceYen == "0")
        #expect(reopened.draft.calories == "12.34")
        #expect(reopened.draft.protein == "0")
        #expect(reopened.draft.fat == "1.23")
        #expect(reopened.draft.sugar == "4.56")
        #expect(reopened.draft.carbohydrates == "92233720368547758.07")
        #expect(reopened.draft.nutrientBasisAmount == "0.01")
        #expect(reopened.draft.nutrientBasisUnit == "食")
    }

    @Test func clearingOptionalInputsAlsoClearsTheUnusedBasis() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        // 最後の栄養素も消す。基準が入力欄に残っていても保存はしない。
        state.draft = ProductDraft(
            name: product.name, type: product.type, nutrientBasisAmount: "15", nutrientBasisUnit: "mL"
        )

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Product>()).first)
        #expect(saved.priceYen == nil)
        #expect(saved.calories == nil)
        #expect(saved.protein == nil)
        #expect(saved.fat == nil)
        #expect(saved.sugar == nil)
        #expect(saved.carbohydrates == nil)
        #expect(saved.nutrientBasisAmount == nil)
        #expect(saved.nutrientBasisUnit == nil)
        #expect(saved.image == Data([1, 2, 3]))
        let reopened = ProductFormState(product: saved)
        #expect(reopened.draft.priceYen.isEmpty)
        #expect(reopened.draft.nutrientBasisAmount.isEmpty)
        #expect(reopened.draft.nutrientBasisUnit.isEmpty)
    }

    @Test func changingBasisDoesNotConvertNutrientInputs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        state.draft.nutrientBasisAmount = "1"
        state.draft.nutrientBasisUnit = "杯（大さじ）"

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.calories == 1234)
        #expect(saved.fat == 0)
        #expect(saved.sugar == 1)
        #expect(saved.carbohydrates == Int64.max)
        #expect(saved.nutrientBasisAmount == 100)
        #expect(saved.nutrientBasisUnit == "杯（大さじ）")
    }

    @Test(
        arguments: [
            ProductDraft.Field.priceYen, .calories, .protein, .fat, .sugar, .carbohydrates, .nutrientBasisAmount,
        ],
        ["-1", "1.234"]
    )
    func invalidOptionalInputAppearsInItsOwnField(_ field: ProductDraft.Field, _ input: String) throws {
        try expectOptionalInputRejected(input, field: field, reason: .invalidFormat)
    }

    @Test(arguments: [
        (ProductDraft.Field.priceYen, "9223372036854775808", ProductDraft.FailureReason.outOfRange),
        (.calories, "92233720368547758.08", .outOfRange),
        (.nutrientBasisAmount, "92233720368547758.08", .outOfRange),
        (.nutrientBasisAmount, "", .required),
        (.nutrientBasisAmount, "0", .mustBePositive),
        (.nutrientBasisUnit, "　 ", .required),
    ])
    func optionalInputExplainsRangeAndRequiredBasis(
        _ field: ProductDraft.Field, _ input: String, _ reason: ProductDraft.FailureReason
    ) throws {
        try expectOptionalInputRejected(input, field: field, reason: reason)
    }

    @Test func selectedPhotoIsSavedWithNewProductOnlyAfterSaving() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        var state = ProductFormState()
        state.draft = ProductDraft(name: "写真付き商品", type: "しょうゆ")
        let image = try ProductPhotoPickerTests.imageData()
        let request = state.photo.beginLoading()
        state.photo.complete(.success(image), request: request)

        #expect(!context.hasChanges)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Product>()) == 0)
        #expect(state.image == image)

        let id = try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.id == id)
        #expect(saved.image == image)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(ProductFormState(product: saved).image == image)
    }

    @Test(arguments: [false, true])
    func photoReplacementOrRemovalDoesNotChangeProductUntilSave(_ remove: Bool) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        let image = try ProductPhotoPickerTests.imageData()
        let request = state.photo.beginLoading()
        state.photo.complete(.success(image), request: request)
        if remove {
            state.photo.remove()
        }
        let expected = remove ? nil : image

        #expect(state.image == expected)
        #expect(product.image == Data([1, 2, 3]))
        #expect(!context.hasChanges)
        let before = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(before.image == Data([1, 2, 3]))

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.image == expected)
        #expect(saved.id == product.id)
        #expect(ProductFormState(product: saved).image == expected)
    }

    @Test func photoReadFailurePreservesAllDraftFieldsAndSavedImage() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        state.draft = ProductDraft(
            name: " 編集中 ", type: " みそ ", priceYen: "398", calories: "10.25", protein: "2.5", fat: "1.23",
            sugar: "4.56", carbohydrates: "8.5", nutrientBasisAmount: "100", nutrientBasisUnit: "g"
        )
        let request = state.photo.beginLoading()

        state.photo.complete(.failure(.loading(StoreError.unavailable)), request: request)

        #expect(state.draft.name == " 編集中 ")
        #expect(state.draft.type == " みそ ")
        #expect(state.draft.priceYen == "398")
        #expect(state.draft.calories == "10.25")
        #expect(state.draft.protein == "2.5")
        #expect(state.draft.fat == "1.23")
        #expect(state.draft.sugar == "4.56")
        #expect(state.draft.carbohydrates == "8.5")
        #expect(state.draft.nutrientBasisAmount == "100")
        #expect(state.draft.nutrientBasisUnit == "g")
        #expect(state.image == Data([1, 2, 3]))
        #expect(state.photo.error?.message != nil)
        #expect(!context.hasChanges)
        #expect(state.savedProductID == nil)
        expectOptionalValues(product)

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.image == Data([1, 2, 3]))
        #expect(saved.name == "編集中")
    }

    @Test(arguments: [false, true])
    func photoSaveFailureKeepsChangeForRetry(_ remove: Bool) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        state.draft.name = " 編集後 "
        let image = try ProductPhotoPickerTests.imageData()
        let request = state.photo.beginLoading()
        state.photo.complete(.success(image), request: request)
        if remove {
            state.photo.remove()
        }
        let expected = remove ? nil : image
        let failing = ProductActions(context: context) { _ in .failure(StoreError.unavailable) }

        let result = state.save(using: failing) { _ in Issue.record("保存失敗を成功として通知した") }

        guard case .failure(.persistence) = result else {
            Issue.record("保存失敗が返されなかった")
            return
        }
        #expect(state.savedProductID == nil)
        #expect(state.draft.name == " 編集後 ")
        #expect(state.image == expected)
        #expect(product.image == Data([1, 2, 3]))
        #expect(!context.hasChanges)
        let before = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(before.image == Data([1, 2, 3]))

        try state.save(using: ProductActions(context: context)) { _ in }.get()

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        #expect(saved.id == product.id)
        #expect(saved.name == "編集後")
        #expect(saved.image == expected)
        #expect(state.error == nil)
    }

    private func expectOptionalInputRejected(
        _ input: String, field: ProductDraft.Field, reason: ProductDraft.FailureReason
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        var state = ProductFormState(product: product)
        switch field {
        case .priceYen:
            state.draft.priceYen = input
        case .calories:
            state.draft.calories = input
        case .protein:
            state.draft.protein = input
        case .fat:
            state.draft.fat = input
        case .sugar:
            state.draft.sugar = input
        case .carbohydrates:
            state.draft.carbohydrates = input
        case .nutrientBasisAmount:
            state.draft.nutrientBasisAmount = input
        case .nutrientBasisUnit:
            state.draft.nutrientBasisUnit = input
        case .name, .type:
            Issue.record("任意欄以外はこの検証の対象外")
            return
        }
        let before = state.draft
        var notifications = 0

        let result = state.save(using: ProductActions(context: context)) { _ in notifications += 1 }

        guard case .failure(.validation(let validation)) = result else {
            Issue.record("任意欄の不正入力を拒否しなかった")
            return
        }
        #expect(validation == ProductDraft.ValidationError(field: field, reason: reason))
        #expect(state.validationMessage(for: field) != nil)
        #expect(state.saveErrorMessage == nil)
        #expect(state.savedProductID == nil)
        #expect(notifications == 0)
        #expect(state.draft.name == before.name)
        #expect(state.draft.type == before.type)
        #expect(state.draft.priceYen == before.priceYen)
        #expect(state.draft.calories == before.calories)
        #expect(state.draft.protein == before.protein)
        #expect(state.draft.fat == before.fat)
        #expect(state.draft.sugar == before.sugar)
        #expect(state.draft.carbohydrates == before.carbohydrates)
        #expect(state.draft.nutrientBasisAmount == before.nutrientBasisAmount)
        #expect(state.draft.nutrientBasisUnit == before.nutrientBasisUnit)
        #expect(!context.hasChanges)
        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Product>()).first)
        expectOptionalValues(saved)
    }

    private func expectOriginalOptionalDraft(_ draft: ProductDraft) {
        #expect(draft.priceYen == "0")
        #expect(draft.calories == "12.34")
        #expect(draft.protein.isEmpty)
        #expect(draft.fat == "0")
        #expect(draft.sugar == "0.01")
        #expect(draft.carbohydrates == "92233720368547758.07")
        #expect(draft.nutrientBasisAmount == "15")
        #expect(draft.nutrientBasisUnit == "mL")
    }

    private func makeSavedProduct(in context: ModelContext) throws -> Product {
        let draft = ProductDraft(
            name: "元の商品", type: "しょうゆ", priceYen: "0", calories: "12.34",
            fat: "0", sugar: "0.01", carbohydrates: "92233720368547758.07",
            nutrientBasisAmount: "15", nutrientBasisUnit: "mL"
        )
        return try ProductActions(context: context).create(
            from: draft, image: Data([1, 2, 3]), now: Date(timeIntervalSince1970: 1)
        ).get()
    }

    private func expectOptionalValues(_ product: Product) {
        #expect(product.image == Data([1, 2, 3]))
        #expect(product.priceYen == 0)
        #expect(product.calories == 1234)
        #expect(product.protein == nil)
        #expect(product.fat == 0)
        #expect(product.sugar == 1)
        #expect(product.carbohydrates == Int64.max)
        #expect(product.nutrientBasisAmount == 1500)
        #expect(product.nutrientBasisUnit == "mL")
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
        var selectedIDs: [UUID] = []

        let result = state.save(using: actions) { selectedIDs.append($0) }
        guard case .failure(.validation(let returnedError)) = result else {
            Issue.record("必須項目のエラーが呼び出し元へ返されなかった")
            return
        }
        #expect(returnedError == ProductDraft.ValidationError(field: field, reason: .required))
        #expect(selectedIDs.isEmpty)
        #expect(state.savedProductID == nil)

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
