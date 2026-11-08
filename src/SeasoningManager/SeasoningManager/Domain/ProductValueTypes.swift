import Foundation

/// 項目名を持たない値の検証エラー。入力欄との対応付けはdraftが行う。
nonisolated enum ProductValueError: Error, Equatable, Sendable {
    case required
    case invalidFormat
    case outOfRange
    case mustBePositive
}

/// 前後の空白を除いた、空でない商品名。
struct ProductName: Equatable {
    let value: String

    private init(_ value: String) {
        self.value = value
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.requiredText(input).map(Self.init)
    }
}

/// 前後の空白を除いた、空でない種類。内部の表記は保持する。
struct ProductType: Equatable {
    let value: String

    private init(_ value: String) {
        self.value = value
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.requiredText(input).map(Self.init)
    }
}

/// パッケージ記載の基準単位。前後の空白を除き、空の単位は許さない。
struct NutrientBasisUnit: Equatable {
    let value: String

    private init(_ value: String) {
        self.value = value
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.requiredText(input).map(Self.init)
    }
}

/// 0以上の整数の円。
struct PriceYen: Equatable {
    let value: Int64

    private init(_ value: Int64) {
        self.value = value
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.number(input, decimalPlaces: 0).map(Self.init)
    }
}

/// 0以上、小数点以下2桁までのカロリー。保存値はkcalの100倍。
struct EnergyKcal: Equatable {
    let hundredths: Int64

    private init(_ hundredths: Int64) {
        self.hundredths = hundredths
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.number(input, decimalPlaces: 2).map(Self.init)
    }
}

/// 0以上、小数点以下2桁までの栄養素の質量。保存値はgの100倍。
struct NutrientGrams: Equatable {
    let hundredths: Int64

    private init(_ hundredths: Int64) {
        self.hundredths = hundredths
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.number(input, decimalPlaces: 2).map(Self.init)
    }
}

/// 0より大きく、小数点以下2桁までの基準量。単位は基準単位と組み合わせる。
struct NutrientBasisAmount: Equatable {
    let hundredths: Int64

    private init(_ hundredths: Int64) {
        self.hundredths = hundredths
    }

    static func parse(_ input: String) -> Result<Self, ProductValueError> {
        ProductValueParser.number(input, decimalPlaces: 2).flatMap { amount in
            guard amount > 0 else {
                return .failure(.mustBePositive)
            }

            return .success(Self(amount))
        }
    }
}

private enum ProductValueParser {
    static func trimmed(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requiredText(_ input: String) -> Result<String, ProductValueError> {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return .failure(.required)
        }

        return .success(value)
    }

    static func number(_ input: String, decimalPlaces: Int) -> Result<Int64, ProductValueError> {
        let value = trimmed(input)
        guard !value.isEmpty else {
            return .failure(.required)
        }

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
            components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else {
            return .failure(.invalidFormat)
        }

        let fraction = components.dropFirst().first ?? ""
        guard fraction.count <= decimalPlaces else {
            return .failure(.invalidFormat)
        }

        // 小数点を除き、不足する桁に0を補う。Doubleへの変換・丸めは行わない。
        let digits = components.joined() + String(repeating: "0", count: decimalPlaces - fraction.count)
        var result: Int64 = 0

        for digit in digits.utf8 {
            let (multiplied, multiplicationOverflow) = result.multipliedReportingOverflow(by: 10)
            let (added, additionOverflow) = multiplied.addingReportingOverflow(Int64(digit - 48))
            guard !multiplicationOverflow, !additionOverflow else {
                return .failure(.outOfRange)
            }

            result = added
        }

        return .success(result)
    }
}
