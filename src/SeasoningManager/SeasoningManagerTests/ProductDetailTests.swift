import Foundation
import SwiftData
import Testing
import UIKit
@testable import SeasoningManager

@MainActor
struct ProductDetailTests {
    @Test func savedProductIsSelectedByIDAmongSameNameProducts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = Product(name: "しょうゆ", type: "調味料")
        let second = Product(name: "しょうゆ", type: "調味料")
        first.priceYen = 100
        second.priceYen = 200
        context.insert(first)
        context.insert(second)
        try context.save()

        let reader = ModelContext(container)
        let matches = try reader.fetch(ProductDetailView.descriptor(for: second.id))
        #expect(matches.count == 1)
        let product = try #require(matches.first)
        let detail = try #require(ProductDetailContent(product: product))

        #expect(product.id == second.id)
        #expect(detail.name == "しょうゆ")
        #expect(detail.type == "調味料")
        #expect(detail.price == "200円")
        #expect(!reader.hasChanges)
    }

    @Test func uninsertedProductHasNoDetail() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "保存前", type: "しょうゆ")

        #expect(ProductDetailContent(product: product) == nil)
        #expect(try context.fetch(ProductDetailView.descriptor(for: product.id)).isEmpty)
    }

    @Test func insertedProductOnlyBecomesAvailableAfterSave() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = Product(name: "保存前", type: "しょうゆ")
        context.insert(product)

        #expect(ProductDetailContent(product: product) == nil)
        #expect(try context.fetch(ProductDetailView.descriptor(for: product.id)).isEmpty)

        try context.save()

        let matches = try context.fetch(ProductDetailView.descriptor(for: product.id))
        let saved = try #require(matches.first)
        let detail = try #require(ProductDetailContent(product: saved))
        #expect(detail.name == "保存前")
    }

    @Test func deletedProductHasNoDetailBeforeAndAfterSavingDeletion() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = Product(name: "削除する商品", type: "みそ")
        let productID = product.id
        context.insert(product)
        try context.save()
        let candidates = try context.fetch(ProductDetailView.descriptor(for: productID))
        let candidate = try #require(candidates.first)
        #expect(ProductDetailContent(product: candidate) != nil)

        context.delete(product)

        // Queryの再取得前に候補が残っていても、削除予定のモデルの属性を読まない。
        #expect(ProductDetailContent(product: candidate) == nil)
        try context.save()

        #expect(ProductDetailContent(product: candidate) == nil)
        #expect(try ModelContext(container).fetch(ProductDetailView.descriptor(for: productID)).isEmpty)
    }

    @Test func unsetOptionalValuesRemainUnset() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: " \t\n　", type: "　\n")
        context.insert(product)
        try context.save()

        let detail = try #require(ProductDetailContent(product: product))
        #expect(detail.name == "名前未設定")
        #expect(detail.type == "種類未設定")
        #expect(detail.image == nil)
        #expect(detail.price == "未設定")
        #expect(detail.nutrientBasis == "未設定")
        #expect(detail.calories == "未設定")
        #expect(detail.protein == "未設定")
        #expect(detail.fat == "未設定")
        #expect(detail.sugar == "未設定")
        #expect(detail.carbohydrates == "未設定")
    }

    @Test func registeredValuesKeepTheirOwnFieldsAndUnits() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "  だし \n", type: " 和風 だし　")
        product.priceYen = 0
        product.calories = 1234
        product.protein = 1
        product.fat = 0
        product.sugar = 456
        product.carbohydrates = Int64.max
        product.nutrientBasisAmount = 1500
        product.nutrientBasisUnit = " mL　"
        product.image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.pngData()
        context.insert(product)
        try context.save()

        let detail = try #require(ProductDetailContent(product: product))
        #expect(detail.name == "だし")
        #expect(detail.type == "和風 だし")
        #expect(detail.image != nil)
        #expect(detail.price == "0円")
        #expect(detail.nutrientBasis == "15mLあたり")
        #expect(detail.calories == "12.34 kcal")
        #expect(detail.protein == "0.01 g")
        #expect(detail.fat == "0 g")
        #expect(detail.sugar == "4.56 g")
        #expect(detail.carbohydrates == "92233720368547758.07 g")
    }

    @Test(arguments: [
        (Int64(0), "0 kcal"),
        (1, "0.01 kcal"),
        (10, "0.1 kcal"),
        (100, "1 kcal"),
        (1234, "12.34 kcal"),
        (Int64.max, "92233720368547758.07 kcal"),
    ])
    func hundredthsAreDisplayedWithoutRounding(_ value: Int64, _ expected: String) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        product.calories = value
        product.nutrientBasisAmount = 10000
        product.nutrientBasisUnit = "g"
        context.insert(product)
        try context.save()

        let detail = try #require(ProductDetailContent(product: product))
        #expect(detail.calories == expected)
        #expect(detail.nutrientBasis == "100gあたり")
    }

    @Test(arguments: [nil, 0, -1] as [Int64?])
    func missingOrInvalidBasisAmountIsNotReplacedWithDefault(_ amount: Int64?) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        product.calories = 0
        product.nutrientBasisAmount = amount
        product.nutrientBasisUnit = "g"
        context.insert(product)
        try context.save()

        let detail = try #require(ProductDetailContent(product: product))
        #expect(detail.nutrientBasis == "未設定")
        #expect(detail.calories == "0 kcal")
    }

    @Test(arguments: [nil, "", " \n　"] as [String?])
    func missingBasisUnitIsNotInferred(_ unit: String?) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        product.nutrientBasisAmount = 10000
        product.nutrientBasisUnit = unit
        context.insert(product)
        try context.save()

        let detail = try #require(ProductDetailContent(product: product))
        #expect(detail.nutrientBasis == "未設定")
    }

    @Test func corruptImageUsesPlaceholderWithoutHidingOtherValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "画像が壊れた商品", type: "みそ")
        product.image = Data([0, 1, 2, 3])
        product.priceYen = 398
        context.insert(product)
        try context.save()

        let detail = try #require(ProductDetailContent(product: product))
        #expect(detail.image == nil)
        #expect(detail.name == "画像が壊れた商品")
        #expect(detail.price == "398円")
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
