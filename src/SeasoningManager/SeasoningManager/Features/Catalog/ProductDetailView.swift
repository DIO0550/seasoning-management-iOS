import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ProductDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var products: [Product]
    @Query private var items: [Item]
    @State private var showsDeletionConfirmation = false
    @State private var deletionError: String?

    init(productID: UUID) {
        _products = Query(Self.descriptor(for: productID))
        _items = Query(Self.itemDescriptor(for: productID))
    }

    static func descriptor(for productID: UUID) -> FetchDescriptor<Product> {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == productID })
        descriptor.includePendingChanges = false
        return descriptor
    }

    static func itemDescriptor(for productID: UUID) -> FetchDescriptor<Item> {
        FetchDescriptor<Item>(predicate: #Predicate { $0.product?.id == productID })
    }

    var body: some View {
        Group {
            if let error = _products.fetchError {
                ContentUnavailableView(
                    "商品を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(error.localizedDescription) 一覧に戻って、もう一度商品を選んでください。")
                )
            } else if let product = products.first, let detail = ProductDetailContent(product: product) {
                details(detail)
                    .confirmationDialog(
                        "商品を削除しますか？", isPresented: $showsDeletionConfirmation, titleVisibility: .visible
                    ) {
                        Button("削除する", role: .destructive) {
                            deleteProduct()
                        }
                        .accessibilityIdentifier("product-detail-confirm-delete")

                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("「\(detail.name)」の商品情報と画像を削除します。この操作は取り消せません。")
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink("編集") {
                                ProductFormView(product: product)
                            }
                            .accessibilityIdentifier("product-detail-edit")
                        }
                    }
            } else {
                ContentUnavailableView(
                    "商品が見つかりません",
                    systemImage: "cabinet",
                    description: Text("まだ保存されていないか、削除された商品です。一覧に戻って商品を選んでください。")
                )
            }
        }
        .navigationTitle("商品詳細")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(_ detail: ProductDetailContent) -> some View {
        Form {
            Section("基本情報") {
                ProductDetailRow(label: "名前", value: detail.name)
                    .accessibilityIdentifier("product-detail-name")
                ProductDetailRow(label: "種類", value: detail.type)
                    .accessibilityIdentifier("product-detail-type")
            }

            Section("画像") {
                if let image = detail.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .accessibilityLabel("商品画像")
                } else {
                    Label("画像なし", systemImage: "photo")
                        .foregroundStyle(.secondary)
                }
            }

            Section("価格") {
                ProductDetailRow(label: "価格", value: detail.price)
                    .accessibilityIdentifier("product-detail-price")
            }

            Section("栄養素") {
                ProductDetailRow(label: "基準", value: detail.nutrientBasis)
                ProductDetailRow(label: "カロリー", value: detail.calories)
                ProductDetailRow(label: "タンパク質", value: detail.protein)
                ProductDetailRow(label: "脂質", value: detail.fat)
                ProductDetailRow(label: "糖質", value: detail.sugar)
                ProductDetailRow(label: "炭水化物", value: detail.carbohydrates)
            }

            deletionSection
        }
    }

    private var deletionSection: some View {
        let counts = ProductDeletionCounts(items: items)

        return Section("個体と削除") {
            if let error = _items.fetchError {
                Text("個体の件数を読み込めないため削除できません。\(error.localizedDescription) 一覧に戻って、もう一度商品を選んでください。")
            } else {
                ProductDetailRow(label: "未開封", value: "\(counts.unopened)件")
                    .accessibilityIdentifier("product-detail-unopened")
                ProductDetailRow(label: "使用中", value: "\(counts.inUse)件")
                    .accessibilityIdentifier("product-detail-in-use")
                ProductDetailRow(label: "使い切り履歴", value: "\(counts.history)件")
                    .accessibilityIdentifier("product-detail-history")

                if counts.unknown > 0 {
                    ProductDetailRow(label: "不明な状態", value: "\(counts.unknown)件")
                }

                if !counts.canDelete {
                    Text("個体が紐づいているため削除できません。使い切り履歴や不明な状態の個体も削除不可の対象です。")
                        .accessibilityIdentifier("product-detail-deletion-reason")
                }
            }

            if let deletionError {
                Text(deletionError)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("product-detail-deletion-error")
            }

            Button("商品を削除", role: .destructive) {
                deletionError = nil
                showsDeletionConfirmation = true
            }
            .disabled(_items.fetchError != nil || !counts.canDelete)
            .accessibilityIdentifier("product-detail-delete")
        }
    }

    private func deleteProduct() {
        guard let product = products.first, !product.isDeleted, product.modelContext === modelContext else {
            deletionError = "商品が見つかりません。一覧に戻って商品を選び直してください。"
            return
        }

        // 確認中に個体が増えていても、保存境界で最新の件数を再検査する。
        switch ProductActions(context: modelContext).delete(product, confirmed: true) {
        case .success:
            dismiss()
        case .failure(let error):
            switch error {
            case .productHasItems(let count):
                deletionError = "個体が\(count)件紐づいているため削除できません。一覧に戻って最新の件数を確認してください。"
            case .pendingChanges:
                deletionError = "ほかの変更が保存されていません。保存が完了してから、もう一度「商品を削除」を押してください。"
            case .productNotInContext:
                deletionError = "商品が見つかりません。一覧に戻って商品を選び直してください。"
            case .persistence(let underlying):
                deletionError = "削除を保存できませんでした。\(underlying.localizedDescription) もう一度「商品を削除」を押してください。"
            case .deletionNotConfirmed, .validation:
                deletionError = "削除できませんでした。一覧に戻って商品を選び直し、もう一度確認してください。"
            }
        }
    }
}

/// 在庫だけでなく履歴と未知の状態も、削除を妨げる個体として数える。
struct ProductDeletionCounts {
    private(set) var unopened = 0
    private(set) var inUse = 0
    private(set) var history = 0
    private(set) var unknown = 0

    var canDelete: Bool {
        unopened + inUse + history + unknown == 0
    }

    init(items: [Item]) {
        for item in items {
            switch item.status {
            case .unopened?:
                unopened += 1
            case .inUse?:
                inUse += 1
            case .consumed?:
                history += 1
            case nil:
                unknown += 1
            }
        }
    }
}

private struct ProductDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)、\(value)")
    }
}

/// 削除されたモデルの属性を読まず、保存済みの商品だけを表示用の値へ移す。
struct ProductDetailContent {
    let name: String
    let type: String
    let image: UIImage?
    let price: String
    let nutrientBasis: String
    let calories: String
    let protein: String
    let fat: String
    let sugar: String
    let carbohydrates: String

    init?(product: Product) {
        guard !product.isDeleted, let context = product.modelContext else {
            return nil
        }

        // 未保存の挿入が取得候補に含まれても詳細には表示しない。
        guard !context.insertedModelsArray.contains(where: { $0 === product }) else {
            return nil
        }

        name = Self.text(product.name, fallback: "名前未設定")
        type = Self.text(product.type, fallback: "種類未設定")
        image = product.image.flatMap { UIImage(data: $0) }
        price = product.priceYen.map { "\($0)円" } ?? "未設定"
        nutrientBasis = Self.basis(amount: product.nutrientBasisAmount, unit: product.nutrientBasisUnit)
        calories = Self.quantity(product.calories, unit: "kcal")
        protein = Self.quantity(product.protein, unit: "g")
        fat = Self.quantity(product.fat, unit: "g")
        sugar = Self.quantity(product.sugar, unit: "g")
        carbohydrates = Self.quantity(product.carbohydrates, unit: "g")
    }

    private static func text(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallback
        }

        return trimmed
    }

    private static func basis(amount: Int64?, unit: String?) -> String {
        guard let amount, amount > 0, let unit else {
            return "未設定"
        }

        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUnit.isEmpty else {
            return "未設定"
        }

        return "\(decimal(amount))\(trimmedUnit)あたり"
    }

    private static func quantity(_ value: Int64?, unit: String) -> String {
        guard let value else {
            return "未設定"
        }

        return "\(decimal(value)) \(unit)"
    }

    private static func decimal(_ value: Int64) -> String {
        // 浮動小数点へ変換せず、100倍整数の小数2桁を正確に戻す。
        let whole = value.magnitude / 100
        let fraction = value.magnitude % 100
        let sign = value < 0 ? "-" : ""
        guard fraction != 0 else {
            return "\(sign)\(whole)"
        }

        if fraction.isMultiple(of: 10) {
            return "\(sign)\(whole).\(fraction / 10)"
        }

        let digits = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(sign)\(whole).\(digits)"
    }
}
