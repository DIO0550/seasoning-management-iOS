import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ProductListView: View {
    @Query(sort: [SortDescriptor(\Product.type), SortDescriptor(\Product.name)])
    private var products: [Product]

    var body: some View {
        Group {
            if products.isEmpty {
                ContentUnavailableView {
                    Label("商品はまだありません", systemImage: "cabinet")
                } description: {
                    Text("商品を登録すると、名前と種類をここで確認できます。")
                } actions: {
                    NavigationLink("商品を登録") {
                        ProductFormView()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(products, id: \.persistentModelID) { product in
                    let productID = product.id

                    NavigationLink {
                        ProductDetailView(productID: productID)
                    } label: {
                        ProductListRow(product: product)
                    }
                }
            }
        }
        .navigationTitle("商品一覧")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProductFormView()
                } label: {
                    Label("商品を登録", systemImage: "plus")
                }
                .accessibilityIdentifier("product-list-register")
            }
        }
    }
}

private struct ProductListRow: View {
    let product: Product

    private var displayName: String {
        let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return "名前未設定"
        }

        return name
    }

    private var displayType: String {
        let type = product.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else {
            return "種類未設定"
        }

        return type
    }

    var body: some View {
        let counts = product.stockCounts

        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)

                Text("種類: \(displayType)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("未開封: \(counts.unopened)本")
                Text("使用中: \(counts.inUse)本")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "商品名、\(displayName)、種類、\(displayType)、未開封、\(counts.unopened)本、使用中、\(counts.inUse)本"
        )
    }

    private var thumbnail: some View {
        Group {
            if let data = product.image, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

#if DEBUG
    private struct ProductListPreview: View {
        private let containerResult: Result<ModelContainer, Error>

        init(seed: () throws -> (products: [Product], items: [Item])) {
            do {
                let (products, items) = try seed()
                let schema = Schema([Product.self, Item.self])
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(for: schema, configurations: [configuration])

                for product in products {
                    container.mainContext.insert(product)
                }
                for item in items {
                    container.mainContext.insert(item)
                }
                try container.mainContext.save()

                containerResult = .success(container)
            } catch {
                containerResult = .failure(error)
            }
        }

        var body: some View {
            switch containerResult {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                ContentUnavailableView(
                    "プレビューの準備に失敗しました",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            }
        }
    }

    // 旧ストアの欠損表示も確認できるよう、プレビュー専用のデータに保存当時の文字列を復元する。
    private func previewProduct(name: String, type: String) throws -> Product {
        let seed = try ProductDraft(name: "プレビュー", type: "プレビュー").validated().get()
        let product = Product(values: seed)
        product.setValue(forKey: \.name, to: name)
        product.setValue(forKey: \.type, to: type)
        return product
    }

    #Preview("商品なし") {
        ProductListPreview { ([], []) }
    }

    #Preview("商品あり・欠損・同名・長い名前") {
        ProductListPreview {
            (
                [
                    try previewProduct(name: "丸大豆しょうゆ", type: "しょうゆ"),
                    try previewProduct(name: "丸大豆しょうゆ", type: "しょうゆ"),
                    try previewProduct(name: "  米みそ  ", type: "  みそ  "),
                    try previewProduct(name: " \n\t ", type: "　\n"),
                    try previewProduct(name: "　\t", type: "しお"),
                    try previewProduct(name: "本みりん", type: " \n"),
                    try previewProduct(name: "商品名が長くても最後まで確認できる、国産丸大豆を使った減塩しょうゆ", type: "しょうゆ"),
                ], []
            )
        }
    }

    #Preview("画像あり・なし・破損と在庫") {
        ProductListPreview {
            let pictured = try previewProduct(name: "丸大豆しょうゆ", type: "しょうゆ")
            pictured.image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
                UIColor.white.setFill()
                context.fill(CGRect(x: 29, y: 14, width: 22, height: 8))
                context.fill(CGRect(x: 22, y: 24, width: 36, height: 44))
            }.pngData()

            let missing = try previewProduct(name: "米みそ", type: "みそ")
            let corrupt = try previewProduct(name: "本みりん", type: "みりん")
            corrupt.image = Data([0, 1, 2, 3])
            let openingDate = Date(timeIntervalSince1970: 1_700_000_000)
            let consumedDate = openingDate.addingTimeInterval(86_400)
            let unknown = Item(product: pictured)
            unknown.setValue(forKey: \.statusRawValue, to: "futureStatus")
            let inUse = Item(product: pictured)
            try inUse.open(on: openingDate, now: consumedDate).get()

            let consumed = Item(product: pictured)
            let otherConsumed = Item(product: corrupt)
            for item in [consumed, otherConsumed] {
                try item.open(on: openingDate, now: consumedDate).get()
                try item.consume(on: consumedDate, now: consumedDate).get()
            }

            return (
                [pictured, missing, corrupt],
                [Item(product: pictured), Item(product: pictured), inUse, consumed, unknown, otherConsumed]
            )
        }
    }
#endif
