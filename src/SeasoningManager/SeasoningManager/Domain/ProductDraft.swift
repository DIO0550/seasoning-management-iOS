import Foundation

/// 編集中の文字列を保持し、画面と保存直前で共通の入力検証を行う。
struct ProductDraft {
    var name: String = ""
    var type: String = ""
    var priceYen: String = ""
    var calories: String = ""
    var protein: String = ""
    var fat: String = ""
    var sugar: String = ""
    var carbohydrates: String = ""
    var nutrientBasisAmount: String = ""
    var nutrientBasisUnit: String = ""

    nonisolated enum Field: Equatable, Sendable {
        case name, type, priceYen, calories, protein, fat, sugar, carbohydrates
        case nutrientBasisAmount, nutrientBasisUnit
    }

    nonisolated enum FailureReason: Equatable, Sendable {
        case required, invalidFormat, outOfRange, mustBePositive
    }

    nonisolated struct ValidationError: Error, Equatable, Sendable {
        let field: Field
        let reason: FailureReason
    }

    func validated() -> Result<ProductValues, ValidationError> {
        ProductValues.validate(self)
    }
}
