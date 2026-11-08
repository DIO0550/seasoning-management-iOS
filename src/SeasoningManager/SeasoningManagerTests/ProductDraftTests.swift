import Testing

@testable import SeasoningManager

@MainActor
struct ProductDraftTests {
    typealias Field = ProductDraft.Field
    typealias ValidationError = ProductDraft.ValidationError

    @Test func newDraftStartsWithBlankInputs() {
        let draft = ProductDraft()

        #expect(draft.name.isEmpty)
        #expect(draft.type.isEmpty)
        #expect(draft.priceYen.isEmpty)
        #expect(draft.calories.isEmpty)
        #expect(draft.protein.isEmpty)
        #expect(draft.fat.isEmpty)
        #expect(draft.sugar.isEmpty)
        #expect(draft.carbohydrates.isEmpty)
        #expect(draft.nutrientBasisAmount.isEmpty)
        #expect(draft.nutrientBasisUnit.isEmpty)
    }

    @Test(arguments: ["", " \t\n　", "\u{00A0}\u{2003}\u{202F}\u{3000}\r\n"])
    func rejectsBlankRequiredText(input: String) {
        var draft = ProductDraft(name: input, type: "調味料")
        #expect(draft.validated() == .failure(ValidationError(field: .name, reason: .required)))

        draft.name = "だし"
        draft.type = input
        #expect(draft.validated() == .failure(ValidationError(field: .type, reason: .required)))
    }

    @Test func trimsSurroundingWhitespaceAndKeepsInternalText() throws {
        let draft = ProductDraft(
            name: "\u{00A0} だし　しょうゆ \n",
            type: "　和風  だし\t",
            priceYen: "\t398　",
            calories: "\u{2003}12.34\n",
            nutrientBasisAmount: "　1\t",
            nutrientBasisUnit: "\n 杯（ 大さじ ）\u{202F}"
        )
        let values = try draft.validated().get()

        #expect(values.name.value == "だし　しょうゆ")
        #expect(values.type.value == "和風  だし")
        #expect(values.priceYen?.value == 398)
        #expect(values.nutrition?.amounts.calories?.hundredths == 1234)
        #expect(values.nutrition?.basisAmount.hundredths == 100)
        #expect(values.nutrition?.basisUnit.value == "杯（ 大さじ ）")
        #expect(draft.calories == "\u{2003}12.34\n")
    }

    @Test(arguments: ["", " \t\n　", "\u{00A0}\u{2003}\u{202F}"])
    func blankNumbersRemainUnset(input: String) throws {
        let draft = ProductDraft(
            name: "だし", type: "調味料", priceYen: input,
            calories: input, protein: input, fat: input, sugar: input, carbohydrates: input,
            nutrientBasisAmount: "100", nutrientBasisUnit: "g"
        )
        let values = try draft.validated().get()

        #expect(values.priceYen?.value == nil)
        #expect(values.nutrition == nil)
    }

    @Test func explicitZeroRemainsZero() throws {
        let draft = ProductDraft(
            name: "だし", type: "調味料", priceYen: "0",
            calories: "0", protein: "0.0", fat: "0.00", sugar: "00", carbohydrates: "000.00",
            nutrientBasisAmount: "0.01", nutrientBasisUnit: "食"
        )
        let values = try draft.validated().get()

        #expect(values.priceYen?.value == 0)
        #expect(values.nutrition?.amounts.calories?.hundredths == 0)
        #expect(values.nutrition?.amounts.protein?.hundredths == 0)
        #expect(values.nutrition?.amounts.fat?.hundredths == 0)
        #expect(values.nutrition?.amounts.sugar?.hundredths == 0)
        #expect(values.nutrition?.amounts.carbohydrates?.hundredths == 0)
        #expect(values.nutrition?.basisAmount.hundredths == 1)
    }

    @Test func nutrientFieldsRemainIndependent() throws {
        let draft = ProductDraft(
            name: "だし", type: "調味料", calories: "12.34", protein: "0.01", fat: "1.2", sugar: "0.02",
            carbohydrates: "4.56", nutrientBasisAmount: "15", nutrientBasisUnit: "mL"
        )
        let values = try draft.validated().get()

        #expect(values.nutrition?.amounts.calories?.hundredths == 1234)
        #expect(values.nutrition?.amounts.protein?.hundredths == 1)
        #expect(values.nutrition?.amounts.fat?.hundredths == 120)
        #expect(values.nutrition?.amounts.sugar?.hundredths == 2)
        #expect(values.nutrition?.amounts.carbohydrates?.hundredths == 456)
        #expect(values.nutrition?.basisAmount.hundredths == 1500)
        #expect(values.nutrition?.basisUnit.value == "mL")
    }

    @Test func oneNutrientDoesNotPopulateOthers() throws {
        let values = try draftWithNumericInput("4.56", field: .sugar).validated().get()

        #expect(values.nutrition?.amounts.calories?.hundredths == nil)
        #expect(values.nutrition?.amounts.protein?.hundredths == nil)
        #expect(values.nutrition?.amounts.fat?.hundredths == nil)
        #expect(values.nutrition?.amounts.sugar?.hundredths == 456)
        #expect(values.nutrition?.amounts.carbohydrates?.hundredths == nil)
    }

    @Test(arguments: [
        ("0", Int64(0)), ("1", Int64(100)), ("0.01", Int64(1)), ("1.2", Int64(120)),
        ("12.34", Int64(1234)), ("92233720368547758.07", Int64.max),
        ("00000000000000000000000000000012.34", Int64(1234)),
    ])
    func scalesDecimalsExactly(input: String, expected: Int64) throws {
        let values = try draftWithNumericInput(input, field: .calories).validated().get()

        #expect(values.nutrition?.amounts.calories?.hundredths == expected)
    }

    @Test(arguments: ["92233720368547758.08", "92233720368547759", "9223372036854775807", "99999999999999999999999"])
    func rejectsScaledOverflow(input: String) {
        let draft = draftWithNumericInput(input, field: .calories)

        #expect(draft.validated() == .failure(ValidationError(field: .calories, reason: .outOfRange)))
    }

    @Test(arguments: [
        "-1", "+1", "1.234", "1.230", "1e2", "1,000", "abc", "NaN", "Infinity", "1 g",
        ".", "1.", ".1", "1 2", "1\t2", "1\n2", "1　2", "1.2.3", "１", "١", "1,2",
    ])
    func rejectsInvalidDecimalFormat(input: String) {
        let draft = draftWithNumericInput(input, field: .calories)

        #expect(draft.validated() == .failure(ValidationError(field: .calories, reason: .invalidFormat)))
        #expect(draft.calories == input)
    }

    @Test(arguments: ["1.23", "1.0", "1.", "-1", "+1", "1e2", "1,000", "abc", "NaN", "1 2", "１"])
    func priceRejectsAnythingExceptUnsignedIntegers(input: String) {
        let draft = draftWithNumericInput(input, field: .priceYen)

        #expect(draft.validated() == .failure(ValidationError(field: .priceYen, reason: .invalidFormat)))
    }

    @Test func priceAllowsInt64MaximumWithoutScaling() throws {
        let values = try draftWithNumericInput("9223372036854775807", field: .priceYen).validated().get()

        #expect(values.priceYen?.value == Int64.max)
    }

    @Test(arguments: ["9223372036854775808", "99999999999999999999999"])
    func rejectsPriceOverflow(input: String) {
        let draft = draftWithNumericInput(input, field: .priceYen)

        #expect(draft.validated() == .failure(ValidationError(field: .priceYen, reason: .outOfRange)))
    }

    @Test(arguments: [
        Field.priceYen, .calories, .protein, .fat, .sugar, .carbohydrates, .nutrientBasisAmount,
    ])
    func identifiesEachInvalidNumericField(field: Field) {
        let draft = draftWithNumericInput("abc", field: field)

        #expect(draft.validated() == .failure(ValidationError(field: field, reason: .invalidFormat)))
    }

    @Test(arguments: [Field.calories, .protein, .fat, .sugar, .carbohydrates])
    func everyNutrientIncludingZeroRequiresBasis(field: Field) {
        var draft = draftWithNumericInput("0", field: field)
        draft.nutrientBasisAmount = ""

        #expect(draft.validated() == .failure(ValidationError(field: .nutrientBasisAmount, reason: .required)))
    }

    @Test(arguments: ["0", "0.0", "0.00"])
    func basisAmountMustBePositive(input: String) {
        let draft = draftWithNumericInput(input, field: .nutrientBasisAmount)

        #expect(draft.validated() == .failure(ValidationError(field: .nutrientBasisAmount, reason: .mustBePositive)))
    }

    @Test(arguments: ["", " \t\n　", "\u{00A0}\u{2003}\u{202F}"])
    func nutrientInputRequiresNonblankBasisUnit(input: String) {
        var draft = draftWithNumericInput("0", field: .calories)
        draft.nutrientBasisUnit = input

        #expect(draft.validated() == .failure(ValidationError(field: .nutrientBasisUnit, reason: .required)))
    }

    @Test func basisAcceptsExactUpperLimitAndRejectsOverflow() throws {
        let values = try draftWithNumericInput("92233720368547758.07", field: .nutrientBasisAmount).validated().get()
        #expect(values.nutrition?.basisAmount.hundredths == Int64.max)

        let overflow = draftWithNumericInput("92233720368547758.08", field: .nutrientBasisAmount)
        #expect(overflow.validated() == .failure(ValidationError(field: .nutrientBasisAmount, reason: .outOfRange)))
    }

    @Test func clearingLastNutrientDiscardsBasisAndRetainsDraftInput() throws {
        var draft = draftWithNumericInput("1", field: .calories)
        let original = try draft.validated().get()
        draft.calories = ""
        // 基準だけの不正入力も、全栄養素空欄の場合は保存対象にしない。
        draft.nutrientBasisAmount = "abc"
        draft.nutrientBasisUnit = "mL"
        let cleared = try draft.validated().get()

        #expect(original.nutrition?.amounts.calories?.hundredths == 100)
        #expect(original.nutrition?.basisAmount.hundredths == 10000)
        #expect(cleared.nutrition == nil)
        #expect(draft.nutrientBasisAmount == "abc")
        #expect(draft.nutrientBasisUnit == "mL")
    }

    @Test func changingBasisDoesNotConvertNutrientValues() throws {
        var draft = draftWithNumericInput("12.34", field: .calories)
        let original = try draft.validated().get()
        draft.nutrientBasisAmount = "15"
        draft.nutrientBasisUnit = "mL"
        let changed = try draft.validated().get()

        #expect(changed.nutrition?.amounts.calories?.hundredths == original.nutrition?.amounts.calories?.hundredths)
        #expect(changed.nutrition?.basisAmount.hundredths == 1500)
        #expect(changed.nutrition?.basisUnit.value == "mL")
    }

    @Test func returnsTheFirstInvalidFieldInValidationOrder() {
        var draft = ProductDraft(
            name: "", type: "", priceYen: "abc", calories: "abc", protein: "abc", fat: "abc",
            sugar: "abc", carbohydrates: "abc", nutrientBasisAmount: "abc", nutrientBasisUnit: ""
        )

        #expect(draft.validated() == .failure(ValidationError(field: .name, reason: .required)))
        draft.name = "だし"
        #expect(draft.validated() == .failure(ValidationError(field: .type, reason: .required)))
        draft.type = "調味料"
        #expect(draft.validated() == .failure(ValidationError(field: .priceYen, reason: .invalidFormat)))
        draft.priceYen = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .calories, reason: .invalidFormat)))
        draft.calories = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .protein, reason: .invalidFormat)))
        draft.protein = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .fat, reason: .invalidFormat)))
        draft.fat = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .sugar, reason: .invalidFormat)))
        draft.sugar = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .carbohydrates, reason: .invalidFormat)))
        draft.carbohydrates = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .nutrientBasisAmount, reason: .invalidFormat)))
        draft.nutrientBasisAmount = "0"
        #expect(draft.validated() == .failure(ValidationError(field: .nutrientBasisAmount, reason: .mustBePositive)))
        draft.nutrientBasisAmount = "1"
        #expect(draft.validated() == .failure(ValidationError(field: .nutrientBasisUnit, reason: .required)))
    }

    private func draftWithNumericInput(_ input: String, field: Field) -> ProductDraft {
        var draft = ProductDraft(
            name: "だし", type: "調味料", nutrientBasisAmount: "100", nutrientBasisUnit: "g"
        )

        switch field {
        case .priceYen:
            draft.priceYen = input
        case .calories:
            draft.calories = input
        case .protein:
            draft.protein = input
        case .fat:
            draft.fat = input
        case .sugar:
            draft.sugar = input
        case .carbohydrates:
            draft.carbohydrates = input
        case .nutrientBasisAmount:
            draft.calories = "1"
            draft.nutrientBasisAmount = input
        case .name, .type, .nutrientBasisUnit:
            Issue.record("数値以外の欄を指定した: \(field)")
        }

        return draft
    }
}
