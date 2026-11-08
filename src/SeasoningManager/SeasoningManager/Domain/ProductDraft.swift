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
        let validatedName: ProductName
        switch value(name, field: .name, using: ProductName.parse) {
        case .success(let parsed):
            validatedName = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedType: ProductType
        switch value(type, field: .type, using: ProductType.parse) {
        case .success(let parsed):
            validatedType = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedPriceYen: PriceYen?
        switch optionalValue(priceYen, field: .priceYen, using: PriceYen.parse) {
        case .success(let parsed):
            validatedPriceYen = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedCalories: EnergyKcal?
        switch optionalValue(calories, field: .calories, using: EnergyKcal.parse) {
        case .success(let parsed):
            validatedCalories = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedProtein: NutrientGrams?
        switch optionalValue(protein, field: .protein, using: NutrientGrams.parse) {
        case .success(let parsed):
            validatedProtein = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedFat: NutrientGrams?
        switch optionalValue(fat, field: .fat, using: NutrientGrams.parse) {
        case .success(let parsed):
            validatedFat = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedSugar: NutrientGrams?
        switch optionalValue(sugar, field: .sugar, using: NutrientGrams.parse) {
        case .success(let parsed):
            validatedSugar = parsed
        case .failure(let error):
            return .failure(error)
        }

        let validatedCarbohydrates: NutrientGrams?
        switch optionalValue(carbohydrates, field: .carbohydrates, using: NutrientGrams.parse) {
        case .success(let parsed):
            validatedCarbohydrates = parsed
        case .failure(let error):
            return .failure(error)
        }

        let amounts = ProductNutrition.Amounts.create(
            calories: validatedCalories, protein: validatedProtein, fat: validatedFat,
            sugar: validatedSugar, carbohydrates: validatedCarbohydrates
        )
        guard let amounts else {
            return .success(
                ProductValues(
                    name: validatedName, type: validatedType, priceYen: validatedPriceYen, nutrition: nil
                )
            )
        }

        let basisAmount: NutrientBasisAmount
        switch value(nutrientBasisAmount, field: .nutrientBasisAmount, using: NutrientBasisAmount.parse) {
        case .success(let parsed):
            basisAmount = parsed
        case .failure(let error):
            return .failure(error)
        }

        return value(nutrientBasisUnit, field: .nutrientBasisUnit, using: NutrientBasisUnit.parse).map { unit in
            ProductValues(
                name: validatedName, type: validatedType, priceYen: validatedPriceYen,
                nutrition: ProductNutrition(amounts: amounts, basisAmount: basisAmount, basisUnit: unit)
            )
        }
    }

    private func value<Value>(
        _ input: String, field: Field, using parse: (String) -> Result<Value, ProductValueError>
    ) -> Result<Value, ValidationError> {
        parse(input).mapError { error in
            let reason: FailureReason

            switch error {
            case .required:
                reason = .required
            case .invalidFormat:
                reason = .invalidFormat
            case .outOfRange:
                reason = .outOfRange
            case .mustBePositive:
                reason = .mustBePositive
            }

            return ValidationError(field: field, reason: reason)
        }
    }

    private func optionalValue<Value>(
        _ input: String, field: Field, using parse: (String) -> Result<Value, ProductValueError>
    ) -> Result<Value?, ValidationError> {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(nil)
        }

        return value(input, field: field, using: parse).map { $0 }
    }
}
