import Foundation

/// 全項目の検証を通った商品情報。モデルの生成・更新はこの値を受け取る。
struct ProductValues: Equatable {
    let name: String
    let type: String
    let priceYen: Int64?
    let nutrition: ProductNutrition?

    private init(name: String, type: String, priceYen: Int64?, nutrition: ProductNutrition?) {
        self.name = name
        self.type = type
        self.priceYen = priceYen
        self.nutrition = nutrition
    }

    static func validate(_ draft: ProductDraft) -> Result<Self, ProductDraft.ValidationError> {
        let validatedName: String
        switch Input.requiredText(draft.name, field: .name) {
        case .success(let value):
            validatedName = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedType: String
        switch Input.requiredText(draft.type, field: .type) {
        case .success(let value):
            validatedType = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedPrice: Int64?
        switch Input.number(draft.priceYen, field: .priceYen, decimalPlaces: 0) {
        case .success(let value):
            validatedPrice = value
        case .failure(let error):
            return .failure(error)
        }

        return ProductNutrition.validate(draft).map { nutrition in
            Self(name: validatedName, type: validatedType, priceYen: validatedPrice, nutrition: nutrition)
        }
    }
}

/// 一つ以上の栄養値と、全栄養値に共通する正の基準量・単位。数値は実際の値を100倍した整数。
struct ProductNutrition: Equatable {
    let calories: Int64?
    let protein: Int64?
    let fat: Int64?
    let sugar: Int64?
    let carbohydrates: Int64?
    let basisAmount: Int64
    let basisUnit: String

    private init(
        calories: Int64?, protein: Int64?, fat: Int64?, sugar: Int64?, carbohydrates: Int64?,
        basisAmount: Int64, basisUnit: String
    ) {
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.sugar = sugar
        self.carbohydrates = carbohydrates
        self.basisAmount = basisAmount
        self.basisUnit = basisUnit
    }

    fileprivate static func validate(_ draft: ProductDraft) -> Result<Self?, ProductDraft.ValidationError> {
        let validatedCalories: Int64?
        switch Input.number(draft.calories, field: .calories, decimalPlaces: 2) {
        case .success(let value):
            validatedCalories = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedProtein: Int64?
        switch Input.number(draft.protein, field: .protein, decimalPlaces: 2) {
        case .success(let value):
            validatedProtein = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedFat: Int64?
        switch Input.number(draft.fat, field: .fat, decimalPlaces: 2) {
        case .success(let value):
            validatedFat = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedSugar: Int64?
        switch Input.number(draft.sugar, field: .sugar, decimalPlaces: 2) {
        case .success(let value):
            validatedSugar = value
        case .failure(let error):
            return .failure(error)
        }

        let validatedCarbohydrates: Int64?
        switch Input.number(draft.carbohydrates, field: .carbohydrates, decimalPlaces: 2) {
        case .success(let value):
            validatedCarbohydrates = value
        case .failure(let error):
            return .failure(error)
        }

        // 全項目の変換に成功したので、nil は空欄、0 は入力済み。
        guard
            [validatedCalories, validatedProtein, validatedFat, validatedSugar, validatedCarbohydrates]
                .contains(where: { $0 != nil })
        else {
            return .success(nil)
        }

        let amount: Int64?
        switch Input.number(draft.nutrientBasisAmount, field: .nutrientBasisAmount, decimalPlaces: 2) {
        case .success(let value):
            amount = value
        case .failure(let error):
            return .failure(error)
        }

        guard let amount else {
            return .failure(.init(field: .nutrientBasisAmount, reason: .required))
        }

        guard amount > 0 else {
            return .failure(.init(field: .nutrientBasisAmount, reason: .mustBePositive))
        }

        return Input.requiredText(draft.nutrientBasisUnit, field: .nutrientBasisUnit).map { unit in
            Self(
                calories: validatedCalories, protein: validatedProtein, fat: validatedFat,
                sugar: validatedSugar, carbohydrates: validatedCarbohydrates,
                basisAmount: amount, basisUnit: unit
            )
        }
    }
}

private enum Input {
    static func trimmed(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requiredText(_ input: String, field: ProductDraft.Field) -> Result<String, ProductDraft.ValidationError>
    {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return .failure(ProductDraft.ValidationError(field: field, reason: .required))
        }

        return .success(value)
    }

    static func number(_ input: String, field: ProductDraft.Field, decimalPlaces: Int) -> Result<
        Int64?, ProductDraft.ValidationError
    > {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return .success(nil)
        }

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
            components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else {
            return .failure(ProductDraft.ValidationError(field: field, reason: .invalidFormat))
        }

        let fraction = components.dropFirst().first ?? ""
        guard fraction.count <= decimalPlaces else {
            return .failure(ProductDraft.ValidationError(field: field, reason: .invalidFormat))
        }

        // 小数点を除き、不足する桁に0を補う。Doubleへの変換・丸めは行わない。
        let digits = components.joined() + String(repeating: "0", count: decimalPlaces - fraction.count)
        var result: Int64 = 0

        for digit in digits.utf8 {
            let (multiplied, multiplicationOverflow) = result.multipliedReportingOverflow(by: 10)
            let (added, additionOverflow) = multiplied.addingReportingOverflow(Int64(digit - 48))
            guard !multiplicationOverflow, !additionOverflow else {
                return .failure(ProductDraft.ValidationError(field: field, reason: .outOfRange))
            }

            result = added
        }

        return .success(result)
    }
}
