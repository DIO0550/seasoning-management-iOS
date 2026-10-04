import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ProductModelTests {
    @Test func newProductStartsWithUnsetOptionalValues() {
        let beforeCreation = Date()
        let product = Product(name: "しょうゆ", type: "調味料")

        #expect(product.name == "しょうゆ")
        #expect(product.type == "調味料")
        #expect(product.updatedAt >= beforeCreation)
        #expect(product.updatedAt <= Date())
        expectUnsetValues(product)
    }

    @Test func productsRetainIDsAndValuesAfterReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("products.store")
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let populatedID = UUID()
        let image = Data([0, 1, 2, 3, 255])
        var unsetID: UUID?
        var zeroID: UUID?

        // 書き込み側のコンテナを破棄し、SQLiteストアからの復元を確認する。
        do {
            let container = try makeContainer(at: storeURL)
            let writer = ModelContext(container)
            let unset = Product(name: "しょうゆ", type: "調味料", updatedAt: updatedAt)
            let zero = Product(name: "しょうゆ", type: "調味料", updatedAt: updatedAt)
            unsetID = unset.id
            zeroID = zero.id
            #expect(unset.id != zero.id)

            zero.priceYen = 0
            zero.calories = 0
            zero.protein = 0
            zero.fat = 0
            zero.sugar = 0
            zero.carbohydrates = 0
            zero.nutrientBasisAmount = 10000
            zero.nutrientBasisUnit = "g"

            let populated = Product(
                id: populatedID, name: "だし", type: "和風 だし", updatedAt: updatedAt
            )
            populated.image = image
            populated.priceYen = 398
            populated.calories = 1234
            populated.protein = 1
            populated.fat = 250
            // 糖質は未設定のまま、炭水化物と独立して保存する。
            populated.carbohydrates = Int64.max
            populated.nutrientBasisAmount = 1500
            populated.nutrientBasisUnit = "mL"

            writer.insert(unset)
            writer.insert(zero)
            writer.insert(populated)
            try writer.save()
        }

        do {
            let container = try makeContainer(at: storeURL)
            let reader = ModelContext(container)
            let products = try reader.fetch(FetchDescriptor<Product>())
            #expect(products.count == 3)
            #expect(Set(products.map(\.id)).count == 3)
            #expect(products.allSatisfy { $0.updatedAt == updatedAt })

            let unset = try #require(products.first { $0.id == unsetID })
            let zero = try #require(products.first { $0.id == zeroID })
            #expect(unset.name == "しょうゆ")
            #expect(zero.name == unset.name)
            #expect(unset.type == "調味料")
            #expect(zero.type == unset.type)
            expectUnsetValues(unset)

            #expect(zero.priceYen == 0)
            #expect(zero.calories == 0)
            #expect(zero.protein == 0)
            #expect(zero.fat == 0)
            #expect(zero.sugar == 0)
            #expect(zero.carbohydrates == 0)
            #expect(zero.nutrientBasisAmount == 10000)
            #expect(zero.nutrientBasisUnit == "g")
            #expect(zero.image == nil)

            let populated = try #require(products.first { $0.id == populatedID })
            #expect(populated.name == "だし")
            #expect(populated.type == "和風 だし")
            #expect(populated.image == image)
            #expect(populated.priceYen == 398)
            #expect(populated.calories == 1234)
            #expect(populated.protein == 1)
            #expect(populated.fat == 250)
            #expect(populated.sugar == nil)
            #expect(populated.carbohydrates == Int64.max)
            #expect(populated.nutrientBasisAmount == 1500)
            #expect(populated.nutrientBasisUnit == "mL")
        }
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([Product.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func expectUnsetValues(_ product: Product) {
        #expect(product.image == nil)
        #expect(product.priceYen == nil)
        #expect(product.calories == nil)
        #expect(product.protein == nil)
        #expect(product.fat == nil)
        #expect(product.sugar == nil)
        #expect(product.carbohydrates == nil)
        #expect(product.nutrientBasisAmount == nil)
        #expect(product.nutrientBasisUnit == nil)
    }
}
