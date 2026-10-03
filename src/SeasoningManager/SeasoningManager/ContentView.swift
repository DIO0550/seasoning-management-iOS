//
//  ContentView.swift
//  SeasoningManager
//
//  Created by DIO on 2026/09/28.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "調味料はまだありません",
                systemImage: "cabinet",
                description: Text("調味料の在庫や使用状況をここで管理します。")
            )
            .navigationTitle("調味料管理")
        }
    }
}

#Preview {
    ContentView()
}
