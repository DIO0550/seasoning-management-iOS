import Foundation
import PhotosUI
import SwiftUI
import UIKit

nonisolated enum ProductPhotoError: Error, Sendable {
    case unavailable
    case invalidImage
    case loading(any Error)
    case cancelled

    var message: String? {
        switch self {
        case .unavailable:
            return "写真のデータを取得できませんでした。もう一度写真を選んでください。"
        case .invalidImage:
            return "画像として読み込めませんでした。別の写真を選んでください。"
        case .loading(let underlying):
            return "写真を読み込めませんでした。\(underlying.localizedDescription) もう一度写真を選んでください。"
        case .cancelled:
            return nil
        }
    }
}

/// 写真の取得と復号をUIのactorから分離する。保存用の元データは加工しない。
actor ProductPhotoLoader {
    func load(using read: @Sendable () async throws -> Data?) async -> Result<Data, ProductPhotoError> {
        do {
            try Task.checkCancellation()
            let data = try await read()
            try Task.checkCancellation()

            guard let data else {
                return .failure(.unavailable)
            }

            guard !data.isEmpty, UIImage(data: data) != nil else {
                return .failure(.invalidImage)
            }

            return .success(data)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.loading(error))
        }
    }

    func preview(for data: Data) -> UIImage? {
        UIImage(data: data)
    }
}

/// 「未変更」と「削除」を分け、読み込み失敗を画像削除として保存しない。
@MainActor
struct ProductPhotoState {
    private enum Change {
        case unchanged
        case replaced(Data)
        case removed
    }

    private var change = Change.unchanged
    private(set) var requestID: UUID?
    private(set) var error: ProductPhotoError?

    var isLoading: Bool {
        requestID != nil
    }

    func image(original: Data?) -> Data? {
        switch change {
        case .unchanged:
            return original
        case .replaced(let data):
            return data
        case .removed:
            return nil
        }
    }

    mutating func beginLoading() -> UUID {
        let id = UUID()
        requestID = id
        error = nil
        return id
    }

    mutating func complete(_ result: Result<Data, ProductPhotoError>, request id: UUID) {
        guard requestID == id else {
            return
        }

        requestID = nil
        switch result {
        case .success(let data):
            change = .replaced(data)
            error = nil
        case .failure(.cancelled):
            error = nil
        case .failure(let failure):
            error = failure
        }
    }

    mutating func remove() {
        cancelLoading()
        change = .removed
    }

    mutating func cancelLoading() {
        requestID = nil
        error = nil
    }
}

struct ProductPhotoPicker: View {
    @Binding var selection: PhotosPickerItem?
    let imageData: Data?
    let isLoading: Bool
    let error: ProductPhotoError?
    let loader: ProductPhotoLoader
    let remove: () -> Void

    @State private var preview: UIImage?

    var body: some View {
        Section {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .accessibilityLabel("商品画像")
                    .accessibilityIdentifier("product-form-photo-preview")
            } else {
                Label(imageData == nil ? "画像なし" : "画像を表示できません", systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("product-form-photo-placeholder")
            }

            PhotosPicker(selection: $selection, matching: .images) {
                Label(imageData == nil ? "写真を追加" : "写真を差し替え", systemImage: "photo.on.rectangle")
            }
            .accessibilityHint("写真ライブラリから商品の画像を1枚選びます。写真は任意です。")
            .accessibilityIdentifier("product-form-photo-select")

            if imageData != nil || isLoading {
                Button("写真を削除", role: .destructive, action: remove)
                    .accessibilityHint("保存すると商品の画像が未設定になります。")
                    .accessibilityIdentifier("product-form-photo-remove")
            }

            if isLoading {
                ProgressView("写真を読み込み中")
                    .accessibilityIdentifier("product-form-photo-loading")
            }

            if let message = error?.message {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityLabel("写真のエラー、\(message)")
                    .accessibilityIdentifier("product-form-photo-error")
            }
        } header: {
            Text("画像")
        } footer: {
            Text("写真は任意です。保存するまで商品には反映されません。")
        }
        .task(id: imageData) {
            guard let imageData else {
                preview = nil
                return
            }

            let image = await loader.preview(for: imageData)
            guard !Task.isCancelled else {
                return
            }

            preview = image
        }
    }
}
