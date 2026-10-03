import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ItemModelTests {
    @Test func newItemsGenerateDistinctIDsAndStartUnopened() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let first = Item(product: product)
        let second = Item(product: product)
        let ids = Set([first.id, second.id])
        #expect(ids.count == 2)
        context.insert(product)
        context.insert(first)
        context.insert(second)
        try context.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)) == ids)
        for item in items {
            #expect(item.product?.id == product.id)
            #expect(item.status == .unopened)
            #expect(item.expirationDate == nil)
            #expect(item.openingDate == nil)
            #expect(item.consumedDate == nil)
        }
    }

    @Test func sharedProductAndItemFieldsSurviveReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Items.store")
        let productID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let opening = Date(timeIntervalSince1970: 1_700_000_000)
        let consumed = opening.addingTimeInterval(86400)
        let expiration = consumed.addingTimeInterval(86400)

        do {
            let container = try makeContainer(url: url)
            let context = ModelContext(container)
            let product = Product(id: productID, name: "しょうゆ", type: "調味料")
            let first = Item(id: firstID, product: product)
            let second = Item(
                id: secondID, product: product, expirationDate: expiration,
                status: .consumed, openingDate: opening, consumedDate: consumed,
                updatedAt: consumed
            )
            context.insert(product)
            context.insert(first)
            context.insert(second)
            try context.save()
        }

        let reopened = try makeContainer(url: url)
        let reader = ModelContext(reopened)
        let items = try reader.fetch(FetchDescriptor<Item>())
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)) == Set([firstID, secondID]))
        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.id == productID)
        #expect(Set((product.items ?? []).map(\.id)) == Set([firstID, secondID]))
        let first = try #require(items.first { $0.id == firstID })
        #expect(first.product?.id == productID)
        #expect(first.status == .unopened)
        #expect(first.expirationDate == nil)
        #expect(first.openingDate == nil)
        #expect(first.consumedDate == nil)
        let second = try #require(items.first { $0.id == secondID })
        #expect(second.product?.id == productID)
        #expect(second.status == .consumed)
        #expect(second.expirationDate == expiration)
        #expect(second.openingDate == opening)
        #expect(second.consumedDate == consumed)
        #expect(second.updatedAt == consumed)
    }

    @Test func missingReferenceAndUnknownStatusSurviveReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("MissingReference.store")
        let itemID = UUID()

        do {
            let container = try makeContainer(url: url)
            let writer = ModelContext(container)
            let product = Product(name: "しょうゆ", type: "調味料")
            let item = Item(id: itemID, product: product)
            writer.insert(product)
            writer.insert(item)
            try writer.save()
            item.product = nil
            item.statusRawValue = "futureStatus"
            try writer.save()
        }

        let reopened = try makeContainer(url: url)
        let reader = ModelContext(reopened)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        let saved = try #require(items.first)
        #expect(saved.id == itemID)
        #expect(saved.product == nil)
        #expect(saved.statusRawValue == "futureStatus")
        #expect(saved.status == nil)
        let savedProduct = try #require(try reader.fetch(FetchDescriptor<Product>()).first)
        #expect(savedProduct.items?.isEmpty ?? true)
    }

    @Test func deletingItemPreservesProductAndOtherItem() throws {
        let container = try makeContainer()
        let writer = ModelContext(container)
        let product = Product(name: "しょうゆ", type: "調味料")
        let deleted = Item(product: product)
        let remaining = Item(product: product, status: .inUse, openingDate: Date())
        writer.insert(product)
        writer.insert(deleted)
        writer.insert(remaining)
        try writer.save()
        writer.delete(deleted)
        try writer.save()

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(items.first?.id == remaining.id)
        #expect(items.first?.status == .inUse)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        #expect(products.first?.id == product.id)
        #expect(products.first?.items?.map(\.id) == [remaining.id])
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
