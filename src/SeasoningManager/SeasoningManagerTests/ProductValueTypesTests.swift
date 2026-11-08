import Testing

@testable import SeasoningManager

@MainActor
struct ProductValueTypesTests {
    @Test(arguments: ["", " \t\n　", "\u{00A0}\u{2003}\u{202F}\u{3000}\r\n"])
    func textValuesRejectBlankInput(_ input: String) {
        #expect(ProductName.parse(input) == .failure(.required))
        #expect(ProductType.parse(input) == .failure(.required))
        #expect(NutrientBasisUnit.parse(input) == .failure(.required))
    }

    @Test func textValuesNormalizeOnlySurroundingWhitespace() throws {
        #expect(try ProductName.parse("\u{00A0}だし　しょうゆ\n").get().value == "だし　しょうゆ")
        #expect(try ProductType.parse("\u{2003}和風  だし\t").get().value == "和風  だし")
        #expect(try NutrientBasisUnit.parse("\n杯（ 大さじ ）\u{202F}").get().value == "杯（ 大さじ ）")
    }

    @Test(arguments: [
        ("", ProductValueError.required), ("　", .required), ("-1", .invalidFormat),
        ("1.0", .invalidFormat), ("1.23", .invalidFormat), ("1e2", .invalidFormat),
        ("1,000", .invalidFormat), ("１", .invalidFormat), ("9223372036854775808", .outOfRange),
    ])
    func priceRejectsNonIntegerAndOutOfRangeInput(_ input: String, _ error: ProductValueError) {
        #expect(PriceYen.parse(input) == .failure(error))
    }

    @Test(arguments: [("0", Int64(0)), ("　398\n", 398), ("9223372036854775807", Int64.max)])
    func pricePreservesExactIntegerYen(_ input: String, _ expected: Int64) throws {
        #expect(try PriceYen.parse(input).get().value == expected)
    }

    @Test(arguments: [
        ("0", Int64(0)), ("0.01", 1), ("1.2", 120), ("　12.34\t", 1234),
        ("00000000000000000000000000000012.34", 1234), ("92233720368547758.07", Int64.max),
    ])
    func caloriesAndGramsPreserveExactHundredths(_ input: String, _ expected: Int64) throws {
        #expect(try EnergyKcal.parse(input).get().hundredths == expected)
        #expect(try NutrientGrams.parse(input).get().hundredths == expected)
    }

    @Test(arguments: [
        ("", ProductValueError.required), ("　\t", .required), ("-0.01", .invalidFormat),
        ("+1", .invalidFormat), ("1.234", .invalidFormat), ("1.", .invalidFormat),
        (".1", .invalidFormat), ("1e2", .invalidFormat), ("1 g", .invalidFormat),
        ("1 2", .invalidFormat), ("１", .invalidFormat), ("NaN", .invalidFormat),
        ("92233720368547758.08", .outOfRange), ("99999999999999999999999", .outOfRange),
    ])
    func decimalValuesRejectInvalidInput(_ input: String, _ error: ProductValueError) {
        #expect(EnergyKcal.parse(input) == .failure(error))
        #expect(NutrientGrams.parse(input) == .failure(error))
        #expect(NutrientBasisAmount.parse(input) == .failure(error))
    }

    @Test(arguments: ["0", "0.0", "0.00", "000.00"])
    func basisRequiresMoreThanZero(_ input: String) {
        #expect(NutrientBasisAmount.parse(input) == .failure(.mustBePositive))
    }

    @Test(arguments: [("0.01", Int64(1)), ("　15.0\n", 1500), ("92233720368547758.07", Int64.max)])
    func basisAcceptsExactPositiveBounds(_ input: String, _ expected: Int64) throws {
        #expect(try NutrientBasisAmount.parse(input).get().hundredths == expected)
    }

    @Test func nutrientAmountsRequireAtLeastOneValueAndCountEveryExplicitZero() throws {
        #expect(ProductNutrition.Amounts.create() == nil)
        let calories = try EnergyKcal.parse("0").get()
        let grams = try NutrientGrams.parse("0").get()
        let amounts = [
            ProductNutrition.Amounts.create(calories: calories),
            ProductNutrition.Amounts.create(protein: grams),
            ProductNutrition.Amounts.create(fat: grams),
            ProductNutrition.Amounts.create(sugar: grams),
            ProductNutrition.Amounts.create(carbohydrates: grams),
        ]

        #expect(amounts.allSatisfy { $0 != nil })
    }

    @Test func oneNutrientLeavesOtherAmountsUnset() throws {
        let sugar = try NutrientGrams.parse("4.56").get()
        let amounts = try #require(ProductNutrition.Amounts.create(sugar: sugar))

        #expect(amounts.calories == nil)
        #expect(amounts.protein == nil)
        #expect(amounts.fat == nil)
        #expect(amounts.sugar == sugar)
        #expect(amounts.carbohydrates == nil)
    }

    @Test func domainValuesComposeWithoutAFormAndKeepIndependentNutrients() throws {
        let calories = try EnergyKcal.parse("12.34").get()
        let protein = try NutrientGrams.parse("0.01").get()
        let fat = try NutrientGrams.parse("1.20").get()
        let carbohydrates = try NutrientGrams.parse("4.56").get()
        let amounts = try #require(
            ProductNutrition.Amounts.create(
                calories: calories, protein: protein, fat: fat, carbohydrates: carbohydrates)
        )
        let nutrition = ProductNutrition(
            amounts: amounts, basisAmount: try NutrientBasisAmount.parse("15").get(),
            basisUnit: try NutrientBasisUnit.parse("mL").get()
        )
        let product = ProductValues(
            name: try ProductName.parse("だし").get(), type: try ProductType.parse("和風 だし").get(),
            priceYen: try PriceYen.parse("398").get(), nutrition: nutrition
        )

        #expect(product.name.value == "だし")
        #expect(product.type.value == "和風 だし")
        #expect(product.priceYen?.value == 398)
        #expect(product.nutrition?.amounts.calories?.hundredths == 1234)
        #expect(product.nutrition?.amounts.protein?.hundredths == 1)
        #expect(product.nutrition?.amounts.fat?.hundredths == 120)
        #expect(product.nutrition?.amounts.sugar == nil)
        #expect(product.nutrition?.amounts.carbohydrates?.hundredths == 456)
        #expect(product.nutrition?.basisAmount.hundredths == 1500)
        #expect(product.nutrition?.basisUnit.value == "mL")
    }
}
