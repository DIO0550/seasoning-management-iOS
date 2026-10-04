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

    init(id: UUID = UUID(), name: String, type: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.updatedAt = updatedAt
    }
}
