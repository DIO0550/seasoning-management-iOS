import Foundation
import SwiftData

/// 入力はdraftで保持し、未保存の変更がないcontextで商品を登録・編集・削除する。
@MainActor
struct ProductActions {
    nonisolated enum ActionError: Error, Sendable {
        case validation(ProductDraft.ValidationError)
        case pendingChanges
        case productNotInContext
        case productHasItems(count: Int)
        case deletionNotConfirmed
        case persistence(any Error)
    }

    private let context: ModelContext
    private let save: @MainActor (ModelContext) -> Result<Void, any Error>

    /// saveはcontextを同期的に保存し、保存成功時だけ.successを返す。保存後に.failureを返す実装は契約外。
    init(
        context: ModelContext,
        save: @escaping @MainActor (ModelContext) -> Result<Void, any Error> = { context in
            Result { try context.save() }
        }
    ) {
        self.context = context
        self.save = save
    }

    func create(from draft: ProductDraft, image: Data? = nil, now: Date = Date()) -> Result<Product, ActionError> {
        let values: ProductDraft.ValidatedValues
        switch draft.validated() {
        case .success(let validated):
            values = validated
        case .failure(let error):
            return .failure(.validation(error))
        }

        if case .failure(let error) = requireCleanContext() {
            return .failure(error)
        }

        let product = Product(name: values.name, type: values.type, updatedAt: now)
        apply(values, image: image, now: now, to: product)
        context.insert(product)

        return saveOrRollback().map { product }
    }

    /// 同じcontextの保存済み商品を編集する。imageのnilは画像の削除を表す。
    func update(
        _ product: Product, from draft: ProductDraft, image: Data?, now: Date = Date()
    ) -> Result<Void, ActionError> {
        let values: ProductDraft.ValidatedValues
        switch draft.validated() {
        case .success(let validated):
            values = validated
        case .failure(let error):
            return .failure(.validation(error))
        }

        if case .failure(let error) = requireCleanContext() {
            return .failure(error)
        }

        guard product.modelContext === context else {
            return .failure(.productNotInContext)
        }

        apply(values, image: image, now: now, to: product)
        return saveOrRollback()
    }

    /// 同じcontextの保存済み商品を、紐づく個体が0件で確認済みの場合だけ削除する。
    func delete(_ product: Product, confirmed: Bool) -> Result<Void, ActionError> {
        if case .failure(let error) = requireCleanContext() {
            return .failure(error)
        }

        guard product.modelContext === context else {
            return .failure(.productNotInContext)
        }

        let productID = product.id
        let items = FetchDescriptor<Item>(predicate: #Predicate<Item> { $0.product?.id == productID })
        let count: Int
        switch Result(catching: { try context.fetchCount(items) }) {
        case .success(let value):
            count = value
        case .failure(let error):
            return .failure(.persistence(error))
        }

        guard count == 0 else {
            return .failure(.productHasItems(count: count))
        }

        guard confirmed else {
            return .failure(.deletionNotConfirmed)
        }

        context.delete(product)
        return saveOrRollback()
    }

    private func requireCleanContext() -> Result<Void, ActionError> {
        // rollbackはcontext全体に作用するため、今回以外の未保存変更があれば触らない。
        guard !context.hasChanges else {
            return .failure(.pendingChanges)
        }

        return .success(())
    }

    private func apply(_ values: ProductDraft.ValidatedValues, image: Data?, now: Date, to product: Product) {
        product.name = values.name
        product.type = values.type
        product.image = image
        product.priceYen = values.priceYen
        product.calories = values.calories
        product.protein = values.protein
        product.fat = values.fat
        product.sugar = values.sugar
        product.carbohydrates = values.carbohydrates
        product.nutrientBasisAmount = values.nutrientBasisAmount
        product.nutrientBasisUnit = values.nutrientBasisUnit
        product.updatedAt = now
    }

    private func saveOrRollback() -> Result<Void, ActionError> {
        switch save(context) {
        case .success:
            return .success(())
        case .failure(let error):
            context.rollback()
            return .failure(.persistence(error))
        }
    }
}
