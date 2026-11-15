import Foundation
import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Query private var items: [Item]

    init(itemID: UUID) {
        _items = Query(Self.descriptor(for: itemID))
    }

    static func descriptor(for itemID: UUID) -> FetchDescriptor<Item> {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        descriptor.includePendingChanges = false
        return descriptor
    }

    var body: some View {
        Group {
            if let error = _items.fetchError {
                ContentUnavailableView(
                    "個体を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(error.localizedDescription) 一覧に戻って、もう一度個体を選んでください。")
                )
            } else if let detail = ItemDetailContent(candidates: items) {
                details(detail)
            } else {
                ContentUnavailableView(
                    "個体の詳細を表示できません",
                    systemImage: "shippingbox",
                    description: Text("個体または紐づく商品が見つかりません。一覧に戻って、もう一度個体を選んでください。")
                )
            }
        }
        .navigationTitle("個体詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(_ detail: ItemDetailContent) -> some View {
        Form {
            Section("個体情報") {
                LabeledContent("状態", value: detail.status)
                LabeledContent("賞味期限", value: detail.expiration)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("賞味期限、\(detail.expiration)")
                    .accessibilityIdentifier("item-detail-expiration")
                LabeledContent("開封日", value: detail.opening)
            }

            Section("商品情報") {
                LabeledContent("商品名", value: detail.product.name)
                LabeledContent("種類", value: detail.product.type)
            }
        }
    }
}

struct ItemDetailContent {
    let product: InventoryProductLabels
    let status: String
    let expiration: String
    let opening: String

    init?(candidates: [Item]) {
        guard candidates.count == 1, let item = candidates.first, !item.isDeleted, item.modelContext != nil,
            let product = InventoryProductLabels(product: item.product)
        else {
            return nil
        }

        self.product = product
        status = item.status?.displayName ?? "不明な状態"
        expiration = item.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "期限未設定"
        opening = item.openingDate?.formatted(date: .abbreviated, time: .omitted) ?? "未設定"
    }
}
