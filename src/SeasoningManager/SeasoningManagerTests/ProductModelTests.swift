import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ProductModelTests {
    @Test func sameNameProductsKeepDistinctIDsAndOptionalValues() throws {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let writer = ModelContext(container)
        let unset = Product(name: "しょうゆ", type: "調味料")
        let zero = Product(name: "しょうゆ", type: "調味料")
        zero.priceYen = 0
        zero.calories = 0
        zero.protein = 0
        zero.fat = 0
        zero.sugar = 0
        zero.carbohydrates = 0
        zero.nutrientBasisAmount = 10000
        zero.nutrientBasisUnit = "g"
        zero.image = Data([1, 2, 3])
        writer.insert(unset)
        writer.insert(zero)
        try writer.save()

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        #expect(unset.id != zero.id)
        let savedUnset = try #require(products.first { $0.id == unset.id })
        #expect(savedUnset.priceYen == nil)
        #expect(savedUnset.calories == nil)
        #expect(savedUnset.protein == nil)
        #expect(savedUnset.fat == nil)
        #expect(savedUnset.sugar == nil)
        #expect(savedUnset.carbohydrates == nil)
        #expect(savedUnset.nutrientBasisAmount == nil)
        #expect(savedUnset.nutrientBasisUnit == nil)
        #expect(savedUnset.image == nil)
        let savedZero = try #require(products.first { $0.id == zero.id })
        #expect(savedZero.priceYen == 0)
        #expect(savedZero.calories == 0)
        #expect(savedZero.protein == 0)
        #expect(savedZero.fat == 0)
        #expect(savedZero.sugar == 0)
        #expect(savedZero.carbohydrates == 0)
        #expect(savedZero.nutrientBasisAmount == 10000)
        #expect(savedZero.nutrientBasisUnit == "g")
        #expect(savedZero.image == Data([1, 2, 3]))
    }
}
