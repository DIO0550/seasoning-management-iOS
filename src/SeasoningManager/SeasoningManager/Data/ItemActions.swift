import Foundation
import SwiftData

/// 未保存の変更がないcontextで、個体の登録・日付編集・開封・使い切り・削除を一回の保存として行う。
@MainActor
struct ItemActions {
    nonisolated enum ActionError: Error, Sendable {
        case pendingChanges
        case productNotInContext
        case itemNotInContext
        case deletionNotConfirmed
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

    func open(
        _ item: Item, openingDate: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> Result<Void, ActionError> {
        let rules = ItemRules(status: .inUse, openingDate: openingDate, consumedDate: item.consumedDate)
        return transition(item, from: .unopened, using: rules, now: now, calendar: calendar)
    }

    func consume(
        _ item: Item, consumedDate: Date, now: Date = Date(), calendar: Calendar = .current
    ) -> Result<Void, ActionError> {
        let rules = ItemRules(status: .consumed, openingDate: item.openingDate, consumedDate: consumedDate)
        return transition(item, from: .inUse, using: rules, now: now, calendar: calendar)
    }

    /// 同じcontextの保存済み個体を、状態にかかわらず確認済みの場合だけ削除する。
    func delete(_ item: Item, confirmed: Bool) -> Result<Void, ActionError> {
        guard !context.hasChanges else {
            return .failure(.pendingChanges)
        }

        guard item.modelContext === context else {
            return .failure(.itemNotInContext)
        }

        guard confirmed else {
            return .failure(.deletionNotConfirmed)
        }

        context.delete(item)

        switch save(context) {
        case .success:
            return .success(())
        case .failure(let error):
            context.rollback()
            return .failure(.persistence(error))
        }
    }

    private func transition(
        _ item: Item, from source: ItemStatus, using rules: ItemRules, now: Date, calendar: Calendar
    ) -> Result<Void, ActionError> {
        guard !context.hasChanges else {
            return .failure(.pendingChanges)
        }

        guard item.modelContext === context else {
            return .failure(.itemNotInContext)
        }

        guard let status = item.status else {
            return .failure(.validation(.unknownCurrentStatus))
        }

        // 日付編集と異なり、同状態への再操作も許可しない。
        guard status == source else {
            return .failure(.validation(.invalidTransition))
        }

        switch item.updateState(using: rules, now: now, calendar: calendar) {
        case .success:
            break
        case .failure(let error):
            return .failure(.validation(error))
        }

        switch save(context) {
        case .success:
            return .success(())
        case .failure(let error):
            context.rollback()
            return .failure(.persistence(error))
        }
    }
}
