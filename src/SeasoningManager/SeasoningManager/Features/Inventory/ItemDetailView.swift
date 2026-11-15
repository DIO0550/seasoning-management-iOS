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
            } else {
                switch ItemDetailContent.resolve(candidates: items) {
                case .success(let detail):
                    details(detail)
                case .failure(.notFound):
                    ContentUnavailableView(
                        "個体が見つかりません",
                        systemImage: "shippingbox",
                        description: Text("在庫一覧に戻って、表示されている個体を選んでください。")
                    )
                case .failure(.duplicateID):
                    ContentUnavailableView(
                        "個体を特定できません",
                        systemImage: "exclamationmark.triangle",
                        description: Text("同じIDの個体が複数あります。在庫一覧に戻ってください。")
                    )
                }
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
    nonisolated enum Unavailable: Error, Equatable, Sendable {
        case notFound
        case duplicateID
    }

    let product: InventoryProductLabels
    let status: String
    let expiration: String
    let opening: String

    static func resolve(candidates: [Item]) -> Result<Self, Unavailable> {
        if candidates.count > 1 {
            return .failure(.duplicateID)
        }

        guard let item = candidates.first, !item.isDeleted, item.modelContext != nil else {
            return .failure(.notFound)
        }

        return .success(Self(item: item))
    }

    private init(item: Item) {
        product = InventoryProductLabels(product: item.product)
        status = item.status?.displayName ?? "不明な状態"
        expiration = item.expirationDate?.formatted(date: .abbreviated, time: .omitted) ?? "期限未設定"
        opening = item.openingDate?.formatted(date: .abbreviated, time: .omitted) ?? "未設定"
    }
}
