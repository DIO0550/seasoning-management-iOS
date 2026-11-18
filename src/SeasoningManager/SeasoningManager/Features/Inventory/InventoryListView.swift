import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct InventoryListView: View {
    @Query private var items: [Item]
    @State private var expirationReferenceDate = Date.now

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
        let availableItems = items.filter { !$0.isDeleted && $0.modelContext != nil }
        let now = expirationReferenceDate

        Group {
            if let error = _items.fetchError {
                ContentUnavailableView(
                    "在庫を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(error.localizedDescription) アプリを開き直してください。")
                )
            } else if availableItems.isEmpty {
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
                    inventorySection(for: .unopened, items: availableItems, now: now)
                    inventorySection(for: .inUse, items: availableItems, now: now)
                }
            }
        }
        .navigationDestination(for: ItemDetailRoute.self) { route in
            ItemDetailView(itemID: route.itemID)
        }
        .onAppear {
            expirationReferenceDate = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            expirationReferenceDate = .now
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
    private func inventorySection(for status: ItemStatus, items: [Item], now: Date) -> some View {
        let matchingItems = items.filter { $0.status == status }

        if !matchingItems.isEmpty {
            Section(status.displayName) {
                ForEach(matchingItems, id: \.persistentModelID) { item in
                    NavigationLink(value: ItemDetailRoute(itemID: item.id)) {
                        InventoryItemRow(item: item, status: status, now: now)
                    }
                }
            }
        }
    }
}

private nonisolated struct ItemDetailRoute: Hashable {
    let itemID: UUID
}

struct InventoryItemRow: View {
    let item: Item
    let status: ItemStatus
    let now: Date

    var productLabels: InventoryProductLabels {
        InventoryProductLabels(product: item.product)
    }

    func expirationPresentation(calendar: Calendar = .current) -> InventoryExpirationPresentation {
        InventoryExpirationPresentation(expirationDate: item.expirationDate, now: now, calendar: calendar)
    }

    var body: some View {
        let product = productLabels
        let expiration = expirationPresentation()

        VStack(alignment: .leading, spacing: 4) {
            Text(product.name)
                .font(.headline)
            Group {
                Text("種類: \(product.type)")
                InventoryExpirationLabel(text: expiration.rowText, warningColor: expiration.warningColor)
                Text(status.displayName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct InventoryExpirationPresentation {
    let rowText: String
    let detailText: String
    let warningColor: Color?

    init(expirationDate: Date?, now: Date, calendar: Calendar) {
        let dateStyle = Date.FormatStyle(
            date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone
        )
        let dateText = expirationDate?.formatted(dateStyle) ?? "期限未設定"
        let warning: (text: String, color: Color)?
        switch ExpirationState.calculate(expirationDate: expirationDate, now: now, calendar: calendar) {
        case .success(.expired):
            warning = ("期限切れ", .red)
        case .success(.expiringSoon):
            warning = ("期限が近い", .orange)
        case .success(.normal), .success(.unset), .failure:
            warning = nil
        }

        let text = warning.map { "\(dateText)（\($0.text)）" } ?? dateText
        detailText = text
        rowText = expirationDate == nil ? text : "賞味期限: \(text)"
        warningColor = warning?.color
    }
}

struct InventoryExpirationLabel: View {
    let text: String
    let warningColor: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let warningColor {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(warningColor)
                    .accessibilityHidden(true)
            }

            Text(text)
                .fontWeight(warningColor == nil ? nil : .semibold)
                .foregroundStyle(warningColor == nil ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InventoryProductLabels {
    let name: String
    let type: String

    init(product: Product?) {
        guard let product, !product.isDeleted, product.modelContext != nil else {
            name = "商品情報なし"
            type = "種類不明"
            return
        }

        let trimmedName = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = product.type.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmedName.isEmpty ? "名前未設定" : trimmedName
        type = trimmedType.isEmpty ? "種類未設定" : trimmedType
    }
}
