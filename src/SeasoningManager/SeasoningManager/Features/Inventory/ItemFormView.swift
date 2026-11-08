import Foundation
import SwiftData
import SwiftUI

/// 商品の選択と日付は保存まで画面内に保持する。
@MainActor
struct ItemFormState {
    var selectedProductID: UUID?
    var hasExpirationDate = false
    var expirationDate = Date()
    private(set) var error: ItemActions.ActionError?
    private(set) var savedItemID: UUID?

    func selectedProduct(in products: [Product]) -> Product? {
        guard let selectedProductID else {
            return nil
        }

        return products.first { product in
            guard !product.isDeleted, product.modelContext != nil else {
                return false
            }

            return product.id == selectedProductID
        }
    }

    mutating func save(
        products: [Product], using actions: ItemActions
    ) -> Result<UUID, ItemActions.ActionError> {
        if let savedItemID {
            return .success(savedItemID)
        }

        guard let product = selectedProduct(in: products) else {
            error = .productNotInContext
            return .failure(.productNotInContext)
        }

        let expiration = hasExpirationDate ? expirationDate : nil
        switch actions.create(for: product, expirationDate: expiration) {
        case .success(let item):
            savedItemID = item.id
            error = nil
            return .success(item.id)
        case .failure(let failure):
            error = failure
            return .failure(failure)
        }
    }

    var saveErrorMessage: String? {
        guard let error else {
            return nil
        }

        switch error {
        case .productNotInContext:
            return "選択した商品が見つかりません。商品を選び直してください。"
        case .pendingChanges:
            return "ほかの変更が保存されていません。変更が保存されてから、もう一度「保存」を押してください。"
        case .persistence(let underlying):
            return "個体を保存できませんでした。\(underlying.localizedDescription) もう一度「保存」を押してください。"
        case .itemNotInContext, .deletionNotConfirmed, .validation:
            return "個体を保存できませんでした。入力内容を確認し、もう一度「保存」を押してください。"
        }
    }
}

struct ItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Product.type), SortDescriptor(\Product.name)])
    private var products: [Product]
    @State private var state = ItemFormState()

    private var canSave: Bool {
        guard _products.fetchError == nil, state.savedItemID == nil else {
            return false
        }

        return state.selectedProduct(in: products) != nil
    }

    var body: some View {
        Group {
            if let error = _products.fetchError {
                ContentUnavailableView(
                    "商品を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(error.localizedDescription) 一覧に戻って開き直してください。")
                )
            } else if products.isEmpty {
                ContentUnavailableView {
                    Label("商品はまだありません", systemImage: "cabinet")
                } description: {
                    Text("先に商品を登録してください。商品を登録したあと、賞味期限を確認して1本を保存できます。")
                } actions: {
                    registerProductLink
                        .buttonStyle(.borderedProminent)
                }
            } else {
                registrationForm
            }
        }
        .navigationTitle("個体を追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
                .accessibilityIdentifier("item-form-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
                    .disabled(!canSave)
                    .accessibilityIdentifier("item-form-save")
            }
        }
    }

    private var registrationForm: some View {
        Form {
            Section("商品を選択") {
                Picker("商品", selection: $state.selectedProductID) {
                    Text("商品を選んでください").tag(nil as UUID?)
                    ForEach(products, id: \.persistentModelID) { product in
                        Text("\(product.name)（\(product.type)）").tag(Optional(product.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("item-form-product")
                registerProductLink
            }

            if let product = state.selectedProduct(in: products) {
                Section("選択した商品") {
                    LabeledContent("名前", value: product.name)
                        .accessibilityIdentifier("item-form-product-name")
                    LabeledContent("種類", value: product.type)
                        .accessibilityIdentifier("item-form-product-type")
                }
            } else if state.selectedProductID != nil {
                Text("選択した商品が見つかりません。商品を選び直してください。")
                    .foregroundStyle(.red)
            }

            Section {
                Toggle("賞味期限を設定", isOn: $state.hasExpirationDate)
                    .accessibilityIdentifier("item-form-has-expiration")
                if state.hasExpirationDate {
                    DatePicker("賞味期限", selection: $state.expirationDate, displayedComponents: .date)
                        .accessibilityIdentifier("item-form-expiration")
                } else {
                    Text("期限未設定")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("賞味期限（任意）")
            } footer: {
                Text("保存すると未開封の個体を1本登録します。賞味期限は省略できます。")
            }

            if let message = state.saveErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("item-form-save-error")
                }
            }
        }
    }

    private var registerProductLink: some View {
        NavigationLink("商品を登録") {
            ProductFormView { productID in
                state.selectedProductID = productID
            }
        }
        .accessibilityIdentifier("item-form-register-product")
    }

    private func save() {
        guard _products.fetchError == nil else {
            return
        }

        switch state.save(products: products, using: ItemActions(context: modelContext)) {
        case .success:
            dismiss()
        case .failure:
            break
        }
    }
}
