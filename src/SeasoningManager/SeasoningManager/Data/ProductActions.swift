import Foundation
import SwiftData

/// 入力はdraftで保持し、未保存の変更がないcontextで商品を登録・編集する。
@MainActor
struct ProductActions {
    nonisolated enum SaveError: Error, Equatable, Sendable {
        case pendingChanges
        case productNotInContext
    }

    private let context: ModelContext
    private let save: @MainActor (ModelContext) throws -> Void

    /// saveは渡されたcontextを同期的に保存し、保存成功時だけ戻る。保存後にthrowする実装は契約外。
    init(
        context: ModelContext,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.save = save
    }

    func create(from draft: ProductDraft, image: Data? = nil, now: Date = Date()) throws -> Product {
        let values = try draft.validated()
        try requireCleanContext()

        let product = Product(name: values.name, type: values.type, updatedAt: now)
        apply(values, image: image, now: now, to: product)
        context.insert(product)
        try saveOrRollback()

        return product
    }

    /// 同じcontextの保存済み商品を編集する。imageのnilは画像の削除を表す。
    func update(_ product: Product, from draft: ProductDraft, image: Data?, now: Date = Date()) throws {
        let values = try draft.validated()
        try requireCleanContext()

        guard product.modelContext === context else {
            throw SaveError.productNotInContext
        }

        apply(values, image: image, now: now, to: product)
        try saveOrRollback()
    }

    private func requireCleanContext() throws {
        // rollbackはcontext全体に作用するため、今回以外の未保存変更があれば触らない。
        guard !context.hasChanges else {
            throw SaveError.pendingChanges
        }
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

    private func saveOrRollback() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
