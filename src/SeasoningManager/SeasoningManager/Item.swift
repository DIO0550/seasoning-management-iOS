import Foundation
import SwiftData

/// 永続化用の個体。商品参照と状態・日付の業務検証は保存操作側で行う。
@Model
final class Item {
    private(set) var id: UUID = UUID()
    @Relationship(deleteRule: .nullify, inverse: \Product.items)
    var product: Product?
    var expirationDate: Date?
    var statusRawValue: String = "unopened"
    var openingDate: Date?
    var consumedDate: Date?
    var updatedAt: Date = Date()

    /// 不明な保存値は保持し、未開封に置き換えない。
    var status: ItemStatus? {
        ItemStatus(rawValue: statusRawValue)
    }

    init(
        id: UUID = UUID(),
        product: Product,
        expirationDate: Date? = nil,
        status: ItemStatus = .unopened,
        openingDate: Date? = nil,
        consumedDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.product = product
        self.expirationDate = expirationDate
        self.statusRawValue = status.rawValue
        self.openingDate = openingDate
        self.consumedDate = consumedDate
        self.updatedAt = updatedAt
    }
}
