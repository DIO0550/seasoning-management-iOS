import Foundation
import SwiftData

/// 未保存の変更がないcontextで、保存済み商品に未開封の個体を1本登録する。
@MainActor
struct ItemActions {
    nonisolated enum ActionError: Error, Sendable {
        case pendingChanges
        case productNotInContext
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

    func create(
        for product: Product, expirationDate: Date? = nil, now: Date = Date()
    ) -> Result<Item, ActionError> {
        // rollbackはcontext全体に作用するため、今回以外の未保存変更があれば触らない。
        guard !context.hasChanges else {
            return .failure(.pendingChanges)
        }

        guard product.modelContext === context else {
            return .failure(.productNotInContext)
        }

        let item = Item(product: product, expirationDate: expirationDate, updatedAt: now)
        context.insert(item)

        switch save(context) {
        case .success:
            return .success(item)
        case .failure(let error):
            context.rollback()
            return .failure(.persistence(error))
        }
    }
}
