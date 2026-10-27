import Foundation
import PhotosUI
import SwiftData
import SwiftUI

/// 入力中は値だけを持ち、保存操作の結果を画面へ返す。
@MainActor
struct ProductFormState {
    var draft = ProductDraft()
    var photo = ProductPhotoState()
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

        draft = ProductDraft(
            name: product.name,
            type: product.type,
            priceYen: product.priceYen.map { String($0) } ?? "",
            calories: Self.decimal(product.calories),
            protein: Self.decimal(product.protein),
            fat: Self.decimal(product.fat),
            sugar: Self.decimal(product.sugar),
            carbohydrates: Self.decimal(product.carbohydrates),
            nutrientBasisAmount: Self.decimal(product.nutrientBasisAmount),
            nutrientBasisUnit: product.nutrientBasisUnit ?? ""
        )
    }

    var isEditing: Bool {
        product != nil
    }

    var image: Data? {
        guard let product else {
            return photo.image(original: nil)
        }

        guard !product.isDeleted, product.modelContext != nil else {
            return photo.image(original: nil)
        }

        return photo.image(original: product.image)
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
            return actions.create(from: draft, image: image).map { $0.id }
        }

        guard !product.isDeleted, product.modelContext != nil else {
            return .failure(.productNotInContext)
        }

        // 写真を操作していないときだけ、保存直前の画像を引き継ぐ。
        let productID = product.id
        return actions.update(product, from: draft, image: image).map { productID }
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
        case .nutrientBasisUnit:
            return "栄養素を入力した場合は、基準単位を入力してください。"
        case .priceYen:
            if validation.reason == .outOfRange {
                return "価格は9223372036854775807円以下で入力してください。"
            }

            return "価格は0以上の半角整数で入力してください。小数・符号・桁区切りは使えません。"
        case .nutrientBasisAmount:
            switch validation.reason {
            case .required:
                return "栄養素を入力した場合は、基準量を入力してください。"
            case .mustBePositive:
                return "基準量は0より大きい値を入力してください。"
            case .invalidFormat:
                return "基準量は0より大きい半角数値を、小数点以下2桁までで入力してください。符号は使えません。"
            case .outOfRange:
                return "基準量は92233720368547758.07以下で入力してください。"
            }
        case .calories, .protein, .fat, .sugar, .carbohydrates:
            if validation.reason == .outOfRange {
                return "栄養値は92233720368547758.07以下で入力してください。"
            }

            return "栄養値は0以上の半角数値を、小数点以下2桁までで入力してください。符号・桁区切りは使えません。"
        }
    }

    var saveErrorMessage: String? {
        guard let error else {
            return nil
        }

        switch error {
        case .validation:
            return nil
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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoTask: Task<Void, Never>?
    @State private var photoLoader = ProductPhotoLoader()

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

            ProductPhotoPicker(
                selection: $selectedPhoto, imageData: state.image, isLoading: state.photo.isLoading,
                error: state.photo.error, loader: photoLoader, remove: removePhoto
            )

            ProductExtraFieldsView(draft: $state.draft, validationMessage: state.validationMessage)

            if let message = state.saveErrorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityLabel("保存エラー、\(message)")
                        .accessibilityIdentifier("product-form-save-error")
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else {
                return
            }

            loadPhoto(item)
        }
        .onDisappear(perform: cancelPhotoLoading)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(state.isEditing ? "商品編集" : "商品登録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル") {
                    cancelPhotoLoading()
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
                .disabled(state.savedProductID != nil || state.photo.isLoading)
                .accessibilityIdentifier("product-form-save")
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        photoTask?.cancel()
        let requestID = state.photo.beginLoading()
        // 同じ写真を選び直した場合も、もう一度読み込めるようにする。
        selectedPhoto = nil

        photoTask = Task {
            let result = await photoLoader.load {
                try await item.loadTransferable(type: Data.self)
            }

            guard !Task.isCancelled, state.photo.requestID == requestID else {
                return
            }

            state.photo.complete(result, request: requestID)
            photoTask = nil
        }
    }

    private func removePhoto() {
        cancelPhotoLoading()
        state.photo.remove()
    }

    private func cancelPhotoLoading() {
        photoTask?.cancel()
        photoTask = nil
        selectedPhoto = nil
        state.photo.cancelLoading()
    }
}
