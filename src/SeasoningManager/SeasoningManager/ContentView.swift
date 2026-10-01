import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "調味料を管理しましょう",
                systemImage: "cabinet",
                description: Text("商品の情報や、開封日・賞味期限をまとめて管理できます。")
            )
            .navigationTitle("調味料管理")
        }
    }
}

#Preview {
    ContentView()
}
