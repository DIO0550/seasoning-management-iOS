import Foundation
import SwiftData

/// 未保存の変更がないcontextで、個体の登録と保存済み個体の日付編集を行う。
@MainActor
struct ItemActions {
    nonisolated enum ActionError: Error, Sendable {
        case pendingChanges
        case productNotInContext
        case itemNotInContext
        case validation(ItemRules.ValidationError)
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

    func updateDates(
        _ item: Item, expirationDate: Date?, openingDate: Date?,
        now: Date = Date(), calendar: Calendar = .current
    ) -> Result<Void, ActionError> {
        // rollbackで他の入力を失わないよう、モデルへ反映する前に保存境界を確認する。
        guard !context.hasChanges else {
            return .failure(.pendingChanges)
        }

        guard item.modelContext === context else {
            return .failure(.itemNotInContext)
        }

        guard let status = item.status else {
            return .failure(.validation(.unknownCurrentStatus))
        }

        let rules = ItemRules(status: status, openingDate: openingDate, consumedDate: item.consumedDate)
        switch item.updateState(using: rules, now: now, calendar: calendar) {
        case .success:
            break
        case .failure(let error):
            return .failure(.validation(error))
        }

        item.expirationDate = expirationDate

        switch save(context) {
        case .success:
            return .success(())
        case .failure(let error):
            context.rollback()
            return .failure(.persistence(error))
        }
    }
}
