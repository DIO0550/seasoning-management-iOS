import Foundation
import SwiftData

/// 永続化用の商品。入力値の業務検証は保存操作側で行う。
@Model
final class Product {
    private(set) var id: UUID = UUID()
    var name: String = ""
    var type: String = ""
    @Attribute(.externalStorage) var image: Data?
    var priceYen: Int64?
    // 栄養値と基準量は実際の値を100倍した整数。
    var calories: Int64?
    var protein: Int64?
    var fat: Int64?
    var sugar: Int64?
    var carbohydrates: Int64?
    var nutrientBasisAmount: Int64?
    var nutrientBasisUnit: String?
    var updatedAt: Date = Date()

    // 個体がある商品の削除は禁止するが、その判定は保存操作側で行う。
    @Relationship(deleteRule: .nullify) var items: [Item]?

    init(id: UUID = UUID(), name: String, type: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.updatedAt = updatedAt
    }
}
