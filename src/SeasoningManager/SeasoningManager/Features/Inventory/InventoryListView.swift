import Foundation
import SwiftData
import SwiftUI

struct InventoryListView: View {
    @Query private var items: [Item]

    init() {
        _items = Query(Self.descriptor())
    }

    static func descriptor() -> FetchDescriptor<Item> {
        FetchDescriptor<Item>(
            predicate: #Predicate {
                $0.statusRawValue == "unopened" || $0.statusRawValue == "inUse"
            },
            sortBy: [SortDescriptor(\Item.updatedAt, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if let error = _items.fetchError {
                ContentUnavailableView(
                    "在庫を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(error.localizedDescription) アプリを開き直してください。")
                )
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("在庫はまだありません", systemImage: "shippingbox")
                } description: {
                    Text("未開封と使用中の個体をここで確認できます。")
                } actions: {
                    NavigationLink("個体を追加") {
                        ItemFormView()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("inventory-empty-add")
                }
            } else {
                List {
                    inventorySection(for: .unopened)
                    inventorySection(for: .inUse)
                }
            }
        }
        .navigationTitle("在庫一覧")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ItemFormView()
                } label: {
                    Label("個体を追加", systemImage: "plus")
                }
                .accessibilityIdentifier("inventory-list-add")
            }
        }
    }

    @ViewBuilder
    private func inventorySection(for status: ItemStatus) -> some View {
        let matchingItems = items.filter { $0.status == status }

        if !matchingItems.isEmpty {
            Section(status.displayName) {
                ForEach(matchingItems, id: \.persistentModelID) { item in
                    InventoryItemRow(item: item, status: status)
                }
            }
        }
    }
}

struct InventoryItemRow: View {
    let item: Item
    let status: ItemStatus

    var productLabels: (name: String, type: String) {
        guard let product = item.product, !product.isDeleted, product.modelContext != nil else {
            return ("商品情報なし", "種類不明")
        }

        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = product.type.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? "名前未設定" : name, type.isEmpty ? "種類未設定" : type)
    }

    var expirationText: String {
        guard let date = item.expirationDate else {
            return "期限未設定"
        }

        return "賞味期限: \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        let product = productLabels

        VStack(alignment: .leading, spacing: 4) {
            Text(product.name)
                .font(.headline)
            Group {
                Text("種類: \(product.type)")
                Text(expirationText)
                Text(status.displayName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
