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
        let modelConfiguration = SeasoningManagerApp.makeConfiguration(for: schema)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private static func makeConfiguration(for schema: Schema) -> ModelConfiguration {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let optionIndex = arguments.firstIndex(of: "--ui-test-store-id"),
                arguments.indices.contains(optionIndex + 1),
                let storeID = UUID(uuidString: arguments[optionIndex + 1])
            {
                // テストごとに分離し、同じテスト内の再起動では同じストアを読む。
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SeasoningManagerUITests-\(storeID.uuidString).store")
                return ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            }
        #endif

        return ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
