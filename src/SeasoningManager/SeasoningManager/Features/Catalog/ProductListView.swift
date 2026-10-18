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
                        ProductRegistrationPlaceholderView()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(products, id: \.persistentModelID) { product in
                    ProductListRow(product: product)
                }
            }
        }
        .navigationTitle("商品一覧")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ProductRegistrationPlaceholderView()
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

private struct ProductRegistrationPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "商品登録機能は準備中です",
            systemImage: "square.and.pencil",
            description: Text("商品一覧に戻るには、画面上部の戻るボタンを使ってください。")
        )
        .navigationTitle("商品登録")
    }
}

private struct ProductListPreview: View {
    private let containerResult: Result<ModelContainer, Error>

    init(products: [Product], items: [Item] = []) {
        do {
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

#Preview("商品なし") {
    ProductListPreview(products: [])
}

#Preview("商品あり・欠損・同名・長い名前") {
    ProductListPreview(products: [
        Product(name: "丸大豆しょうゆ", type: "しょうゆ"),
        Product(name: "丸大豆しょうゆ", type: "しょうゆ"),
        Product(name: "  米みそ  ", type: "  みそ  "),
        Product(name: " \n\t ", type: "　\n"),
        Product(name: "　\t", type: "しお"),
        Product(name: "本みりん", type: " \n"),
        Product(name: "商品名が長くても最後まで確認できる、国産丸大豆を使った減塩しょうゆ", type: "しょうゆ"),
    ])
}

#Preview("画像あり・なし・破損と在庫") {
    let pictured = Product(name: "丸大豆しょうゆ", type: "しょうゆ")
    pictured.image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        UIColor.white.setFill()
        context.fill(CGRect(x: 29, y: 14, width: 22, height: 8))
        context.fill(CGRect(x: 22, y: 24, width: 36, height: 44))
    }.pngData()

    let missing = Product(name: "米みそ", type: "みそ")
    let corrupt = Product(name: "本みりん", type: "みりん")
    corrupt.image = Data([0, 1, 2, 3])
    let openingDate = Date(timeIntervalSince1970: 1_700_000_000)
    let consumedDate = openingDate.addingTimeInterval(86_400)
    let unknown = Item(product: pictured)
    unknown.statusRawValue = "futureStatus"

    return ProductListPreview(
        products: [pictured, missing, corrupt],
        items: [
            Item(product: pictured),
            Item(product: pictured),
            Item(product: pictured, status: .inUse, openingDate: openingDate),
            Item(
                product: pictured, status: .consumed,
                openingDate: openingDate, consumedDate: consumedDate
            ),
            unknown,
            Item(
                product: corrupt, status: .consumed,
                openingDate: openingDate, consumedDate: consumedDate
            ),
        ]
    )
}
