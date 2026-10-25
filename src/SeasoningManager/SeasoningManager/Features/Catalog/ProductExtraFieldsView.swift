import SwiftUI

/// 保存モデルには触れず、任意項目の入力と欄ごとのエラーを表示する。
struct ProductExtraFieldsView: View {
    @Binding var draft: ProductDraft
    let validationMessage: @MainActor (ProductDraft.Field) -> String?

    var body: some View {
        Section {
            numberField("価格", text: $draft.priceYen, unit: "円", field: .priceYen, id: "price")
        } header: {
            Text("価格（任意）")
        } footer: {
            Text("0以上の整数の円で入力します。空欄は未設定、0は0円として保存します。")
        }

        Section {
            numberField("カロリー", text: $draft.calories, unit: "kcal", field: .calories, id: "calories")
            numberField("タンパク質", text: $draft.protein, unit: "g", field: .protein, id: "protein")
            numberField("脂質", text: $draft.fat, unit: "g", field: .fat, id: "fat")
            numberField("糖質", text: $draft.sugar, unit: "g", field: .sugar, id: "sugar")
            numberField("炭水化物", text: $draft.carbohydrates, unit: "g", field: .carbohydrates, id: "carbohydrates")
        } header: {
            Text("栄養素（任意）")
        } footer: {
            Text("各項目は0以上、小数点以下2桁まで入力できます。小数点は「.」を使います。空欄は未設定、0は入力済みです。")
        }

        Section {
            numberField(
                "基準量", text: $draft.nutrientBasisAmount, unit: "", field: .nutrientBasisAmount,
                id: "basis-amount", requirement: "栄養素を入力した場合は必須"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("基準単位")
                    .font(.subheadline)
                TextField("例: g、mL、食", text: $draft.nutrientBasisUnit)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("基準単位、栄養素を入力した場合は必須")
                    .accessibilityHint(validationMessage(.nutrientBasisUnit) ?? "パッケージに書かれた基準単位を入力してください。")
                    .accessibilityIdentifier("product-form-basis-unit")
                fieldError(.nutrientBasisUnit, title: "基準単位", id: "basis-unit")
            }
        } header: {
            Text("栄養素の共通基準")
        } footer: {
            Text(
                "栄養素を1項目でも入力すると基準量と基準単位が必要です。例: 100 g、15 mL、1 食。基準量は0より大きく、小数点以下2桁までです。"
                    + "栄養素が全て空欄なら、基準だけ入力しても保存されません。"
                    + "基準を変えると全ての栄養値の基準が変わります。自動換算はしないため、保存前に各値を見直してください。"
            )
            .accessibilityIdentifier("product-form-basis-guidance")
        }
    }

    private func numberField(
        _ title: String, text: Binding<String>, unit: String, field: ProductDraft.Field, id: String,
        requirement: String = "任意"
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(unit.isEmpty ? title : "\(title)（\(unit)）")
                .font(.subheadline)
            TextField("未設定", text: text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel([title, unit, requirement].filter { !$0.isEmpty }.joined(separator: "、"))
                .accessibilityHint(validationMessage(field) ?? "空欄は未設定です。")
                .accessibilityIdentifier("product-form-\(id)")
            fieldError(field, title: title, id: id)
        }
    }

    @ViewBuilder
    private func fieldError(_ field: ProductDraft.Field, title: String, id: String) -> some View {
        if let message = validationMessage(field) {
            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(title)のエラー、\(message)")
                .accessibilityIdentifier("product-form-\(id)-error")
        }
    }
}
