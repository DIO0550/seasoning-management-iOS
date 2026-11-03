import Foundation
import SwiftData

/// 商品情報の書き込みには検証済みの値を使い、SwiftDataには従来の属性で保存する。
@Model
final class Product {
    // CloudKitで使えない一意制約に頼らず、商品ごとにIDを発行する。
    private(set) var id: UUID = UUID()
    private(set) var name: String = ""
    private(set) var type: String = ""
    @Attribute(.externalStorage) var image: Data?
    private(set) var priceYen: Int64?

    // 栄養値と基準量は実際の値を100倍した整数。未設定と0を区別する。
    private(set) var calories: Int64?
    private(set) var protein: Int64?
    private(set) var fat: Int64?
    private(set) var sugar: Int64?
    private(set) var carbohydrates: Int64?
    private(set) var nutrientBasisAmount: Int64?
    private(set) var nutrientBasisUnit: String?
    private(set) var updatedAt: Date = Date()

    // 個体がある商品の削除拒否は保存操作側で行う。
    @Relationship(deleteRule: .nullify)
    var items: [Item]?

    /// 在庫は個体から都度求め、使い切りと未知の状態は本数に含めない。
    var stockCounts: (unopened: Int, inUse: Int) {
        var counts = (unopened: 0, inUse: 0)

        for item in items ?? [] {
            switch item.status {
            case .unopened?:
                counts.unopened += 1
            case .inUse?:
                counts.inUse += 1
            case .consumed?, nil:
                break
            }
        }

        return counts
    }

    init(id: UUID = UUID(), values: ProductValues, image: Data? = nil, updatedAt: Date = Date()) {
        self.id = id
        update(values: values, image: image, updatedAt: updatedAt)
    }

    func update(values: ProductValues, image: Data?, updatedAt: Date) {
        name = values.name
        type = values.type
        priceYen = values.priceYen
        calories = values.nutrition?.calories
        protein = values.nutrition?.protein
        fat = values.nutrition?.fat
        sugar = values.nutrition?.sugar
        carbohydrates = values.nutrition?.carbohydrates
        nutrientBasisAmount = values.nutrition?.basisAmount
        nutrientBasisUnit = values.nutrition?.basisUnit
        self.image = image
        self.updatedAt = updatedAt
    }
}
