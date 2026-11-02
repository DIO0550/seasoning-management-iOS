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
                        ItemRegistrationPreparationView()
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
                    ItemRegistrationPreparationView()
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

private struct InventoryItemRow: View {
    let item: Item
    let status: ItemStatus

    private var productName: String {
        guard let product = item.product, !product.isDeleted else {
            return "商品情報なし"
        }

        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return "名前未設定"
        }

        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(productName)
                .font(.headline)
            Text(status.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

// 個体登録フォームと保存の接続は後続の Issue で実装する。
private struct ItemRegistrationPreparationView: View {
    var body: some View {
        ContentUnavailableView {
            Label("個体登録は準備中", systemImage: "shippingbox")
        } description: {
            Text("個体の登録機能はまだ利用できません。先に商品の情報を登録できます。商品を登録しても在庫は増えません。")
        } actions: {
            NavigationLink("商品を登録") {
                ProductFormView()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("inventory-preparation-register-product")
        }
        .navigationTitle("個体を追加")
        .navigationBarTitleDisplayMode(.inline)
    }
}
