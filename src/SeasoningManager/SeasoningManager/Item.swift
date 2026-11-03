import Foundation
import SwiftData

/// 商品に属する個体。状態と日付は検証に成功したときだけまとめて更新する。
@Model
final class Item {
    private(set) var id: UUID = UUID()
    @Relationship(deleteRule: .nullify, inverse: \Product.items)
    private(set) var product: Product?
    private(set) var expirationDate: Date?
    private(set) var statusRawValue: String = "unopened"
    private(set) var openingDate: Date?
    private(set) var consumedDate: Date?
    private(set) var updatedAt: Date = Date()

    /// 未知の保存値は保持し、未開封へ補完しない。
    var status: ItemStatus? {
        ItemStatus(rawValue: statusRawValue)
    }

    init(id: UUID = UUID(), product: Product, expirationDate: Date? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.product = product
        self.expirationDate = expirationDate
        self.updatedAt = updatedAt
    }

    func open(on date: Date, now: Date, calendar: Calendar = .current) -> Result<Void, ItemRules.ValidationError> {
        let rules = ItemRules(status: .inUse, openingDate: date, consumedDate: consumedDate)
        return updateState(using: rules, requiring: .unopened, now: now, calendar: calendar)
    }

    func consume(on date: Date, now: Date, calendar: Calendar = .current) -> Result<Void, ItemRules.ValidationError> {
        let rules = ItemRules(status: .consumed, openingDate: openingDate, consumedDate: date)
        return updateState(using: rules, requiring: .inUse, now: now, calendar: calendar)
    }

    func updateDates(
        expirationDate: Date?, openingDate: Date?, now: Date, calendar: Calendar = .current
    ) -> Result<Void, ItemRules.ValidationError> {
        guard let status else {
            return .failure(.unknownCurrentStatus)
        }

        let rules = ItemRules(status: status, openingDate: openingDate, consumedDate: consumedDate)
        return updateState(using: rules, now: now, calendar: calendar).map {
            self.expirationDate = expirationDate
        }
    }

    private func updateState(
        using rules: ItemRules, requiring source: ItemStatus? = nil, now: Date, calendar: Calendar = .current
    ) -> Result<Void, ItemRules.ValidationError> {
        rules.validate(from: status, requiring: source, now: now, calendar: calendar).map { state in
            switch state.stage {
            case .unopened:
                statusRawValue = ItemStatus.unopened.rawValue
                openingDate = nil
                consumedDate = nil
            case .inUse(let opening):
                statusRawValue = ItemStatus.inUse.rawValue
                openingDate = opening
                consumedDate = nil
            case .consumed(let opening, let consumed):
                statusRawValue = ItemStatus.consumed.rawValue
                openingDate = opening
                consumedDate = consumed
            }
            updatedAt = now
        }
    }
}
