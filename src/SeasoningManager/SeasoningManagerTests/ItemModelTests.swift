import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ItemModelTests {
    @Test func freshContainerKeepsNewIndividualsDistinct() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = Item(product: product, updatedAt: updatedAt)
        let second = Item(product: product, updatedAt: updatedAt)

        #expect(first.id != second.id)
        context.insert(product)
        context.insert(first)
        context.insert(second)
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)) == Set([first.id, second.id]))

        for item in items {
            #expect(item.product?.id == product.id)
            #expect(item.status == .unopened)
            #expect(item.expirationDate == nil)
            #expect(item.openingDate == nil)
            #expect(item.consumedDate == nil)
            #expect(item.updatedAt == updatedAt)
        }
    }

    @Test func sharedProductAndItemFieldsSurviveReopeningStore() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("items.store")
        let productID = UUID()
        let unopenedID = UUID()
        let inUseID = UUID()
        let consumedID = UUID()
        let opening = Date(timeIntervalSince1970: 1_700_000_000)
        let consumed = opening.addingTimeInterval(86_400)
        let expiration = consumed.addingTimeInterval(86_400)
        let updatedAt = expiration.addingTimeInterval(86_400)

        // 書き込み側を破棄し、SQLiteストアから関係と各状態を復元する。
        do {
            let container = try makeContainer(url: url)
            let context = ModelContext(container)
            let product = Product(id: productID, name: "しょうゆ", type: "調味料")
            let unopened = Item(id: unopenedID, product: product, updatedAt: updatedAt)
            let inUse = Item(
                id: inUseID, product: product, expirationDate: expiration,
                status: .inUse, openingDate: opening, updatedAt: updatedAt
            )
            let usedUp = Item(
                id: consumedID, product: product, expirationDate: expiration,
                status: .consumed, openingDate: opening, consumedDate: consumed,
                updatedAt: updatedAt
            )

            context.insert(product)
            context.insert(unopened)
            context.insert(inUse)
            context.insert(usedUp)
            try context.save()
        }

        let reopened = try makeContainer(url: url)
        let reader = ModelContext(reopened)
        let items = try reader.fetch(FetchDescriptor<Item>())
        let products = try reader.fetch(FetchDescriptor<Product>())
        let expectedIDs = Set([unopenedID, inUseID, consumedID])
        #expect(items.count == 3)
        #expect(Set(items.map(\.id)) == expectedIDs)
        #expect(items.allSatisfy { $0.product?.id == productID })
        #expect(items.allSatisfy { $0.updatedAt == updatedAt })
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.id == productID)
        #expect(Set((product.items ?? []).map(\.id)) == expectedIDs)

        let unopened = try #require(items.first { $0.id == unopenedID })
        #expect(unopened.status == .unopened)
        #expect(unopened.expirationDate == nil)
        #expect(unopened.openingDate == nil)
        #expect(unopened.consumedDate == nil)

        let inUse = try #require(items.first { $0.id == inUseID })
        #expect(inUse.status == .inUse)
        #expect(inUse.expirationDate == expiration)
        #expect(inUse.openingDate == opening)
        #expect(inUse.consumedDate == nil)

        let usedUp = try #require(items.first { $0.id == consumedID })
        #expect(usedUp.status == .consumed)
        #expect(usedUp.expirationDate == expiration)
        #expect(usedUp.openingDate == opening)
        #expect(usedUp.consumedDate == consumed)
    }

    @Test(arguments: ["", "futureStatus"])
    func missingReferenceAndUnknownStatusSurviveReopeningStore(_ rawValue: String) throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("items.store")
        let itemID = UUID()
        let productID = UUID()

        do {
            let container = try makeContainer(url: url)
            let writer = ModelContext(container)
            let product = Product(id: productID, name: "しょうゆ", type: "調味料")
            let item = Item(id: itemID, product: product)
            writer.insert(product)
            writer.insert(item)
            try writer.save()

            // 同期途中の欠落や将来の保存値を、正常な状態へ置き換えない。
            item.product = nil
            item.statusRawValue = rawValue
            try writer.save()
        }

        let reopened = try makeContainer(url: url)
        let reader = ModelContext(reopened)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        let saved = try #require(items.first)
        #expect(saved.id == itemID)
        #expect(saved.product == nil)
        #expect(saved.statusRawValue == rawValue)
        #expect(saved.status == nil)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.id == productID)
        #expect((product.items ?? []).isEmpty)
    }

    @Test func replacingProductUpdatesBothInverseRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let original = Product(name: "しょうゆ", type: "調味料")
        let replacement = Product(name: "だし", type: "調味料")
        let item = Item(product: original)
        context.insert(original)
        context.insert(replacement)
        context.insert(item)
        try context.save()

        item.product = nil
        try context.save()
        item.product = replacement
        try context.save()

        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<Item>()).first)
        #expect(saved.id == item.id)
        #expect(saved.product?.id == replacement.id)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        let oldProduct = try #require(products.first { $0.id == original.id })
        let newProduct = try #require(products.first { $0.id == replacement.id })
        #expect((oldProduct.items ?? []).isEmpty)
        #expect(newProduct.items?.map(\.id) == [item.id])
    }

    @Test func deletingItemPreservesProductAndOtherItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let deleted = Item(product: product)
        let opening = Date(timeIntervalSince1970: 1_700_000_000)
        let remaining = Item(product: product, status: .inUse, openingDate: opening)
        context.insert(product)
        context.insert(deleted)
        context.insert(remaining)
        try context.save()

        context.delete(deleted)
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(items.first?.id == remaining.id)
        #expect(items.first?.status == .inUse)
        #expect(items.first?.openingDate == opening)
        #expect(items.first?.product?.id == product.id)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        #expect(products.first?.id == product.id)
        #expect(products.first?.items?.map(\.id) == [remaining.id])
    }

    private func makeStoreDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])

        if let url {
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
