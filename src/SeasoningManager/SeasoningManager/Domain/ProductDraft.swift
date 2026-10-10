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

    enum Field: Equatable, Sendable {
        case name, type, priceYen, calories, protein, fat, sugar, carbohydrates
        case nutrientBasisAmount, nutrientBasisUnit
    }

    enum FailureReason: Equatable, Sendable {
        case required, invalidFormat, outOfRange, mustBePositive
    }

    struct ValidationError: Error, Equatable {
        let field: Field
        let reason: FailureReason
    }

    /// 全項目が有効な場合だけ返す。栄養値・基準量は100倍した整数。
    struct ValidatedValues: Equatable {
        let name: String
        let type: String
        let priceYen: Int64?
        let calories: Int64?
        let protein: Int64?
        let fat: Int64?
        let sugar: Int64?
        let carbohydrates: Int64?
        let nutrientBasisAmount: Int64?
        let nutrientBasisUnit: String?
    }

    /// 入力を変更せずに検証する。失敗時は保存可能な値を一部だけ返さない。
    func validated() throws -> ValidatedValues {
        let validatedName = try requiredText(name, field: .name)
        let validatedType = try requiredText(type, field: .type)
        let validatedPrice = try number(priceYen, field: .priceYen, decimalPlaces: 0)
        let validatedCalories = try number(calories, field: .calories, decimalPlaces: 2)
        let validatedProtein = try number(protein, field: .protein, decimalPlaces: 2)
        let validatedFat = try number(fat, field: .fat, decimalPlaces: 2)
        let validatedSugar = try number(sugar, field: .sugar, decimalPlaces: 2)
        let validatedCarbohydrates = try number(carbohydrates, field: .carbohydrates, decimalPlaces: 2)

        // 変換の成否ではなく、元の入力で基準の必要性を判定する。0も入力済み。
        let hasNutrientInput = [calories, protein, fat, sugar, carbohydrates].contains {
            !trimmed($0).isEmpty
        }
        var validatedBasisAmount: Int64?
        var validatedBasisUnit: String?

        if hasNutrientInput {
            guard let amount = try number(nutrientBasisAmount, field: .nutrientBasisAmount, decimalPlaces: 2) else {
                throw ValidationError(field: .nutrientBasisAmount, reason: .required)
            }

            guard amount > 0 else {
                throw ValidationError(field: .nutrientBasisAmount, reason: .mustBePositive)
            }

            validatedBasisAmount = amount
            validatedBasisUnit = try requiredText(nutrientBasisUnit, field: .nutrientBasisUnit)
        }

        return ValidatedValues(
            name: validatedName,
            type: validatedType,
            priceYen: validatedPrice,
            calories: validatedCalories,
            protein: validatedProtein,
            fat: validatedFat,
            sugar: validatedSugar,
            carbohydrates: validatedCarbohydrates,
            nutrientBasisAmount: validatedBasisAmount,
            nutrientBasisUnit: validatedBasisUnit
        )
    }

    private func trimmed(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requiredText(_ input: String, field: Field) throws -> String {
        let value = trimmed(input)
        guard !value.isEmpty else {
            throw ValidationError(field: field, reason: .required)
        }

        return value
    }

    private func number(_ input: String, field: Field, decimalPlaces: Int) throws -> Int64? {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return nil
        }

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
            components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else {
            throw ValidationError(field: field, reason: .invalidFormat)
        }

        let fraction = components.dropFirst().first ?? ""
        guard fraction.count <= decimalPlaces else {
            throw ValidationError(field: field, reason: .invalidFormat)
        }

        // 小数点を除き、不足する桁に0を補う。Doubleへの変換・丸めは行わない。
        let digits = components.joined() + String(repeating: "0", count: decimalPlaces - fraction.count)
        var result: Int64 = 0

        for digit in digits.utf8 {
            let (multiplied, multiplicationOverflow) = result.multipliedReportingOverflow(by: 10)
            let (added, additionOverflow) = multiplied.addingReportingOverflow(Int64(digit - 48))
            guard !multiplicationOverflow, !additionOverflow else {
                throw ValidationError(field: field, reason: .outOfRange)
            }

            result = added
        }

        return result
    }
}
