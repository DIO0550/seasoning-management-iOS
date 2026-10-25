import Foundation
import SwiftData
import SwiftUI

/// 入力中は値だけを持ち、保存操作の結果を画面へ返す。
@MainActor
struct ProductFormState {
    var draft = ProductDraft()
    private(set) var error: ProductActions.ActionError?
    private(set) var savedProductID: UUID?
    private let product: Product?

    init(product: Product? = nil) {
        self.product = product
        guard let product else {
            return
        }

        guard !product.isDeleted, product.modelContext != nil else {
            error = .productNotInContext
            return
        }

        draft.name = product.name
        draft.type = product.type
    }

    var isEditing: Bool {
        product != nil
    }

    /// 保存成功後は完了状態とし、別の登録・編集には新しいフォーム状態を使う。
    mutating func save(
        using actions: ProductActions, onSave: @MainActor (UUID) -> Void
    ) -> Result<UUID, ProductActions.ActionError> {
        if let savedProductID {
            return .success(savedProductID)
        }

        switch persist(using: actions) {
        case .success(let productID):
            savedProductID = productID
            error = nil
            onSave(productID)
            return .success(productID)
        case .failure(let failure):
            error = failure
            return .failure(failure)
        }
    }

    private func persist(using actions: ProductActions) -> Result<UUID, ProductActions.ActionError> {
        guard let product else {
            return actions.create(from: draft).map { $0.id }
        }

        guard !product.isDeleted, product.modelContext != nil else {
            return .failure(.productNotInContext)
        }

        // 入力欄のない情報は保存直前の値を引き継ぎ、基本情報の編集で消さない。
        let values = ProductDraft(
            name: draft.name,
            type: draft.type,
            priceYen: product.priceYen.map { String($0) } ?? "",
            calories: Self.decimal(product.calories),
            protein: Self.decimal(product.protein),
            fat: Self.decimal(product.fat),
            sugar: Self.decimal(product.sugar),
            carbohydrates: Self.decimal(product.carbohydrates),
            nutrientBasisAmount: Self.decimal(product.nutrientBasisAmount),
            nutrientBasisUnit: product.nutrientBasisUnit ?? ""
        )
        let productID = product.id
        return actions.update(product, from: values, image: product.image).map { productID }
    }

    private static func decimal(_ value: Int64?) -> String {
        guard let value else {
            return ""
        }

        // 100倍整数から正確に戻す。Doubleへの変換・丸めは行わない。
        let whole = value.magnitude / 100
        let fraction = value.magnitude % 100
        let sign = value < 0 ? "-" : ""
        guard fraction != 0 else {
            return "\(sign)\(whole)"
        }

        let digits = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(sign)\(whole).\(digits)"
    }

    func validationMessage(for field: ProductDraft.Field) -> String? {
        guard case .validation(let validation) = error, validation.field == field else {
            return nil
        }

        switch field {
        case .name:
            return "名前を入力してください。"
        case .type:
            return "種類を入力してください。"
        default:
            return "入力内容を確認してください。"
        }
    }

    var saveErrorMessage: String? {
        guard let error else {
            return nil
        }

        switch error {
        case .validation(let validation):
            switch validation.field {
            case .name, .type:
                return nil
            default:
                return "登録済みの価格・栄養素の内容を確認できないため、商品を保存できませんでした。入力内容は保持されています。"
            }
        case .pendingChanges:
            return "ほかの変更が保存されていません。変更が保存されてから、もう一度「保存」を押してください。"
        case .persistence(let underlying):
            return "商品を保存できませんでした。\(underlying.localizedDescription) もう一度「保存」を押してください。"
        case .productNotInContext:
            return "編集する商品が見つかりません。一覧に戻って、もう一度商品を選んでください。"
        case .productHasItems, .deletionNotConfirmed:
            return "商品を保存できませんでした。入力内容を確認し、もう一度「保存」を押してください。"
        }
    }
}

struct ProductFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: ProductFormState

    private let onSave: @MainActor (UUID) -> Void

    init(product: Product? = nil, onSave: @escaping @MainActor (UUID) -> Void = { _ in }) {
        _state = State(initialValue: ProductFormState(product: product))
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                TextField("名前", text: $state.draft.name)
                    .accessibilityLabel("名前、必須")
                    .accessibilityHint(state.validationMessage(for: .name) ?? "商品の名前を入力してください。")
                    .accessibilityIdentifier("product-form-name")

                if let message = state.validationMessage(for: .name) {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel("名前のエラー、\(message)")
                        .accessibilityIdentifier("product-form-name-error")
                }

                TextField("種類", text: $state.draft.type)
                    .accessibilityLabel("種類、必須")
                    .accessibilityHint(state.validationMessage(for: .type) ?? "しょうゆ、みそなど、種類を自由に入力してください。")
                    .accessibilityIdentifier("product-form-type")

                if let message = state.validationMessage(for: .type) {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel("種類のエラー、\(message)")
                        .accessibilityIdentifier("product-form-type-error")
                }
            } header: {
                Text("基本情報")
            } footer: {
                Text("名前と種類は必須です。")
            }

            if let message = state.saveErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel("保存エラー、\(message)")
                        .accessibilityIdentifier("product-form-save-error")
                }
            }
        }
        .navigationTitle(state.isEditing ? "商品編集" : "商品登録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル") {
                    dismiss()
                }
                .accessibilityIdentifier("product-form-cancel")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    if case .success = state.save(using: ProductActions(context: modelContext), onSave: onSave) {
                        dismiss()
                    }
                }
                .disabled(state.savedProductID != nil)
                .accessibilityIdentifier("product-form-save")
            }
        }
    }
}
