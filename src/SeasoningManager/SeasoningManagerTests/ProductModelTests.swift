import Foundation
import SwiftData
import Testing

@testable import SeasoningManager

@MainActor
struct ProductModelTests {
    @Test func newProductStartsWithUnsetOptionalValues() throws {
        let beforeCreation = Date()
        let values = try ProductDraft(name: " しょうゆ　", type: " 調味料 ").validated().get()
        let product = Product(values: values)

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
            let unset = try Product(name: "しょうゆ", type: "調味料", updatedAt: updatedAt)
            let zeroValues = try ProductDraft(
                name: "しょうゆ", type: "調味料", priceYen: "0",
                calories: "0", protein: "0", fat: "0", sugar: "0", carbohydrates: "0",
                nutrientBasisAmount: "100", nutrientBasisUnit: "g"
            ).validated().get()
            let zero = Product(values: zeroValues, updatedAt: updatedAt)
            unsetID = unset.id
            zeroID = zero.id
            #expect(unset.id != zero.id)

            let populatedValues = try ProductDraft(
                name: "だし", type: "和風 だし", priceYen: "398",
                calories: "12.34", protein: "0.01", fat: "2.50", carbohydrates: "92233720368547758.07",
                nutrientBasisAmount: "15", nutrientBasisUnit: "mL"
            ).validated().get()
            let populated = Product(id: populatedID, values: populatedValues, image: image, updatedAt: updatedAt)

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

    @Test func removingLastNutrientClearsStoredBasisOnModelUpdate() throws {
        var draft = ProductDraft(
            name: "しょうゆ", type: "調味料", calories: "0",
            nutrientBasisAmount: "100", nutrientBasisUnit: " g　"
        )
        let product = Product(values: try draft.validated().get())
        #expect(product.calories == 0)
        #expect(product.nutrientBasisAmount == 10000)
        #expect(product.nutrientBasisUnit == "g")

        draft.calories = ""
        let editedAt = Date(timeIntervalSince1970: 1_700_000_000)
        product.update(values: try draft.validated().get(), image: nil, updatedAt: editedAt)

        #expect(product.updatedAt == editedAt)
        expectUnsetValues(product)
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

// 表示・保存テスト用。旧データに含まれる未正規化の文字列や欠損もそのまま再現する。
@MainActor
extension Product {
    convenience init(id: UUID = UUID(), name: String, type: String, updatedAt: Date = Date()) throws {
        let draft = ProductDraft(name: "テスト商品", type: "調味料")
        self.init(id: id, values: try draft.validated().get(), updatedAt: updatedAt)
        setValue(forKey: \.name, to: name)
        setValue(forKey: \.type, to: type)
    }

    /// 保存済み商品に別の画面から編集が入った状況を、モデルの更新経路で作る。
    func editFixture(_ edit: (inout ProductDraft) -> Void) throws {
        var draft = ProductFormState(product: self).draft
        edit(&draft)
        update(values: try draft.validated().get(), image: image, updatedAt: updatedAt)
    }
}
