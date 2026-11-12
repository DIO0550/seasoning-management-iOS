import Foundation
import SwiftData
import SwiftUI

struct ProductPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedProductID: UUID?
    let products: [Product]

    var body: some View {
        List(products, id: \.persistentModelID) { product in
            Button {
                selectedProductID = product.id
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(product.name)
                            .foregroundStyle(.primary)
                        Text(product.type)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedProductID == product.id {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityLabel("\(product.name)（\(product.type)）")
            .accessibilityAddTraits(selectedProductID == product.id ? .isSelected : [])
            .accessibilityIdentifier("product-picker-\(product.id.uuidString)")
        }
        .navigationTitle("商品を選択")
        .navigationBarTitleDisplayMode(.inline)
    }
}
