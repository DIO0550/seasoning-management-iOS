//
//  ContentView.swift
//  SeasoningManager
//
//  Created by DIO on 2026/09/28.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ProductListView()
            }
            .tabItem {
                Label("商品", systemImage: "cabinet")
            }

            NavigationStack {
                InventoryListView()
            }
            .tabItem {
                Label("在庫", systemImage: "shippingbox")
            }
        }
    }
}
