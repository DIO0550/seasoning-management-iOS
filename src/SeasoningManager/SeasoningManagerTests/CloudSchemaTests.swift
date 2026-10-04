import CoreData
import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

/// ローカルで確認できるスキーマ条件と、明示的に有効化するCloudKit起動確認。
/// コンテナの生成成功だけでは、CloudKitへの転送成功を保証しない。
@MainActor
struct CloudSchemaTests {
    @Test func generatedAttributesHaveDefaultsOrAreOptionalAndHaveNoUniqueConstraints() throws {
        let model = try makeManagedObjectModel()
        #expect(Set(model.entities.compactMap(\.name)) == Set(["Product", "Item"]))

        for entity in model.entities {
            #expect(entity.uniquenessConstraints.isEmpty)
            for attribute in entity.attributesByName.values {
                #expect(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name ?? "?").\(attribute.name) requires a default or Optional"
                )
                #expect(attribute.attributeType != .undefinedAttributeType)
                #expect(attribute.attributeType != .objectIDAttributeType)
            }
        }
    }

    @Test func generatedRelationshipsAreOptionalWithNullifyAndReciprocalInverses() throws {
        let model = try makeManagedObjectModel()
        let product = try #require(model.entitiesByName["Product"])
        let item = try #require(model.entitiesByName["Item"])
        let items = try #require(product.relationshipsByName["items"])
        let owner = try #require(item.relationshipsByName["product"])
        #expect(items.isToMany)
        #expect(!owner.isToMany)
        #expect(items.destinationEntity === item)
        #expect(owner.destinationEntity === product)
        #expect(items.inverseRelationship === owner)
        #expect(owner.inverseRelationship === items)

        for entity in model.entities {
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.isOptional)
                #expect(relationship.deleteRule == .nullifyDeleteRule)
                let inverse = try #require(relationship.inverseRelationship)
                #expect(inverse.inverseRelationship === relationship)
            }
        }
    }

    @Test func imageIsOptionalBinaryWithExternalStorage() throws {
        let model = try makeManagedObjectModel()
        let product = try #require(model.entitiesByName["Product"])
        let image = try #require(product.attributesByName["image"])
        #expect(image.isOptional)
        #expect(image.attributeType == .binaryDataAttributeType)
        #expect(image.allowsExternalBinaryDataStorage)
    }

    @Test func localStorePreservesImageBytesAndSharedProductAfterReopening() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("LocalSchema.store")
        let productID = UUID()
        let itemIDs = [UUID(), UUID()]
        // 画像属性のバイナリ往復を調べるデータ。画像デコードや容量上限のテストではない。
        let imageBytes = Data((0..<(256 * 1024)).map { UInt8($0 % 251) })

        try autoreleasepool {
            let container = try makeLocalContainer(url: url)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let product = Product(id: productID, name: "しょうゆ", type: "調味料")
            product.image = imageBytes
            context.insert(product)
            for id in itemIDs {
                context.insert(Item(id: id, product: product))
            }
            try context.save()
        }

        try autoreleasepool {
            let container = try makeLocalContainer(url: url)
            let context = ModelContext(container)
            let products = try context.fetch(FetchDescriptor<Product>())
            let items = try context.fetch(FetchDescriptor<Item>())
            #expect(products.count == 1)
            let product = try #require(products.first)
            #expect(product.id == productID)
            #expect(product.image == imageBytes)
            #expect(items.count == 2)
            #expect(Set(items.map(\.id)) == Set(itemIDs))
            #expect(items.allSatisfy { $0.product?.id == productID })
            #expect(Set((product.items ?? []).map(\.id)) == Set(itemIDs))
        }
    }

    #if DEBUG
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["SEASONING_RUN_CLOUD_SCHEMA_TEST"] == "1",
        "CloudKitの起動確認は署名・開発用コンテナ設定後に明示的に実行する"
    ))
    func cloudKitConfiguredContainerCanOpen() throws {
        let identifier = try #require(
            ProcessInfo.processInfo.environment["SEASONING_CLOUDKIT_CONTAINER_ID"]
        )
        try #require(identifier.hasPrefix("iCloud.") && identifier.count > "iCloud.".count)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try autoreleasepool {
            let schema = Schema([Product.self, Item.self])
            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appendingPathComponent("CloudSchema.store"),
                cloudKitDatabase: .private(identifier)
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            // 遅延したストア読み込みの失敗も伝播させる。件数は同期タイミングに依存する。
            let context = ModelContext(container)
            _ = try context.fetchCount(FetchDescriptor<Product>())
            _ = try context.fetchCount(FetchDescriptor<Item>())
            // 非同期のCloudKitセットアップ・転送結果は実機ログで別途確認する。
        }
    }
    #endif

    private func makeManagedObjectModel() throws -> NSManagedObjectModel {
        try #require(NSManagedObjectModel.makeManagedObjectModel(for: [Product.self, Item.self]))
    }

    private func makeLocalContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
