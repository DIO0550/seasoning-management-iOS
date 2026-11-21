//
//  SeasoningManagerApp.swift
//  SeasoningManager
//
//  Created by DIO on 2026/09/28.
//

import Foundation
import SwiftData
import SwiftUI

@main
struct SeasoningManagerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Product.self,
        ])
        do {
            #if DEBUG
                if let container = try SeasoningManagerApp.makeUITestContainer(for: schema) {
                    return container
                }
            #endif

            let modelConfiguration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    #if DEBUG
        private static func makeUITestContainer(for schema: Schema) throws -> ModelContainer? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let optionIndex = arguments.firstIndex(of: "--ui-test-store-id"),
                arguments.indices.contains(optionIndex + 1),
                let storeID = UUID(uuidString: arguments[optionIndex + 1])
            else {
                return nil
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SeasoningManagerUITests-\(storeID.uuidString).store")
            let isNewStore = !FileManager.default.fileExists(atPath: url.path)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            // 全商品を削除した後の再起動でも、初期データを復活させない。
            if isNewStore, let json = ProcessInfo.processInfo.environment["UI_TEST_PRODUCT_TYPES_BY_NAME"] {
                let products = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
                let actions = ProductActions(context: container.mainContext)
                for (name, type) in products {
                    _ = try actions.create(from: ProductDraft(name: name, type: type)).get()
                }
            }
            return container
        }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
