/// 不変条件を満たした値を組み合わせた商品情報。フォームを経由せずに構成できる。
struct ProductValues: Equatable {
    let name: ProductName
    let type: ProductType
    let priceYen: PriceYen?
    let nutrition: ProductNutrition?
}

/// 入力済みの栄養値と、全栄養値に共通する基準。
struct ProductNutrition: Equatable {
    let amounts: Amounts
    let basisAmount: NutrientBasisAmount
    let basisUnit: NutrientBasisUnit

    /// 一つ以上の栄養値を持つ。各項目の未設定と0を区別する。
    struct Amounts: Equatable {
        let calories: EnergyKcal?
        let protein: NutrientGrams?
        let fat: NutrientGrams?
        let sugar: NutrientGrams?
        let carbohydrates: NutrientGrams?

        private init(
            calories: EnergyKcal?, protein: NutrientGrams?, fat: NutrientGrams?,
            sugar: NutrientGrams?, carbohydrates: NutrientGrams?
        ) {
            self.calories = calories
            self.protein = protein
            self.fat = fat
            self.sugar = sugar
            self.carbohydrates = carbohydrates
        }

        static func create(
            calories: EnergyKcal? = nil, protein: NutrientGrams? = nil, fat: NutrientGrams? = nil,
            sugar: NutrientGrams? = nil, carbohydrates: NutrientGrams? = nil
        ) -> Self? {
            guard calories != nil || [protein, fat, sugar, carbohydrates].contains(where: { $0 != nil }) else {
                return nil
            }

            return Self(calories: calories, protein: protein, fat: fat, sugar: sugar, carbohydrates: carbohydrates)
        }
    }
}
