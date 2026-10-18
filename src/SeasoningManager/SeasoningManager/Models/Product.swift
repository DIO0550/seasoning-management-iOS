import Foundation
import SwiftData

/// 永続化用の商品。入力値の業務検証は保存操作側で行う。
@Model
final class Product {
    // CloudKitで使えない一意制約に頼らず、商品ごとにIDを発行する。
    private(set) var id: UUID = UUID()
    var name: String = ""
    var type: String = ""
    @Attribute(.externalStorage) var image: Data?
    var priceYen: Int64?

    // 栄養値と基準量は実際の値を100倍した整数。未設定と0を区別する。
    var calories: Int64?
    var protein: Int64?
    var fat: Int64?
    var sugar: Int64?
    var carbohydrates: Int64?
    var nutrientBasisAmount: Int64?
    var nutrientBasisUnit: String?
    var updatedAt: Date = Date()

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

    init(id: UUID = UUID(), name: String, type: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.updatedAt = updatedAt
    }
}
