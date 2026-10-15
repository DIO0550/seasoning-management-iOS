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
    func validated() -> Result<ValidatedValues, ValidationError> {
        let validatedName: String
        switch requiredText(name, field: .name) {
        case .success(let value):
            validatedName = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedType: String
        switch requiredText(type, field: .type) {
        case .success(let value):
            validatedType = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedPrice: Int64?
        switch number(priceYen, field: .priceYen, decimalPlaces: 0) {
        case .success(let value):
            validatedPrice = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedCalories: Int64?
        switch number(calories, field: .calories, decimalPlaces: 2) {
        case .success(let value):
            validatedCalories = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedProtein: Int64?
        switch number(protein, field: .protein, decimalPlaces: 2) {
        case .success(let value):
            validatedProtein = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedFat: Int64?
        switch number(fat, field: .fat, decimalPlaces: 2) {
        case .success(let value):
            validatedFat = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedSugar: Int64?
        switch number(sugar, field: .sugar, decimalPlaces: 2) {
        case .success(let value):
            validatedSugar = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedCarbohydrates: Int64?
        switch number(carbohydrates, field: .carbohydrates, decimalPlaces: 2) {
        case .success(let value):
            validatedCarbohydrates = value
        case .failure(let error):
            return .failure(error)
        }

        // 変換の成否ではなく、元の入力で基準の必要性を判定する。0も入力済み。
        let hasNutrientInput = [calories, protein, fat, sugar, carbohydrates].contains {
            !trimmed($0).isEmpty
        }
        var validatedBasisAmount: Int64?
        var validatedBasisUnit: String?

        if hasNutrientInput {
            let amount: Int64?
            switch number(nutrientBasisAmount, field: .nutrientBasisAmount, decimalPlaces: 2) {
            case .success(let value):
                amount = value
            case .failure(let error):
                return .failure(error)
            }

            guard let amount else {
                return .failure(ValidationError(field: .nutrientBasisAmount, reason: .required))
            }

            guard amount > 0 else {
                return .failure(ValidationError(field: .nutrientBasisAmount, reason: .mustBePositive))
            }

            validatedBasisAmount = amount
            switch requiredText(nutrientBasisUnit, field: .nutrientBasisUnit) {
            case .success(let value):
                validatedBasisUnit = value
            case .failure(let error):
                return .failure(error)
            }
        }

        return .success(
            ValidatedValues(
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
        )
    }

    private func trimmed(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requiredText(_ input: String, field: Field) -> Result<String, ValidationError> {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return .failure(ValidationError(field: field, reason: .required))
        }

        return .success(value)
    }

    private func number(_ input: String, field: Field, decimalPlaces: Int) -> Result<Int64?, ValidationError> {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return .success(nil)
        }

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
            components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else {
            return .failure(ValidationError(field: field, reason: .invalidFormat))
        }

        let fraction = components.dropFirst().first ?? ""
        guard fraction.count <= decimalPlaces else {
            return .failure(ValidationError(field: field, reason: .invalidFormat))
        }

        // 小数点を除き、不足する桁に0を補う。Doubleへの変換・丸めは行わない。
        let digits = components.joined() + String(repeating: "0", count: decimalPlaces - fraction.count)
        var result: Int64 = 0

        for digit in digits.utf8 {
            let (multiplied, multiplicationOverflow) = result.multipliedReportingOverflow(by: 10)
            let (added, additionOverflow) = multiplied.addingReportingOverflow(Int64(digit - 48))
            guard !multiplicationOverflow, !additionOverflow else {
                return .failure(ValidationError(field: field, reason: .outOfRange))
            }

            result = added
        }

        return .success(result)
    }
}
