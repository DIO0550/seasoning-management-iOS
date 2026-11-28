import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ItemDetailView: View {
    private nonisolated enum Sheet: Identifiable {
        case editDates(Item)
        case open(Item)

        var id: String {
            switch self {
            case .editDates:
                return "editDates"
            case .open:
                return "open"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [Item]
    @State private var expirationReferenceDate = Date.now
    @State private var sheet: Sheet?
    @State private var showsDeletionConfirmation = false
    @State private var deletionError: String?
    #if DEBUG
        @State private var failsNextOpeningSave: Bool
    #endif

    init(itemID: UUID) {
        _items = Query(Self.descriptor(for: itemID))
        #if DEBUG
            _failsNextOpeningSave = State(initialValue: Self.requestsOpeningSaveFailure)
        #endif
    }

    static func descriptor(for itemID: UUID) -> FetchDescriptor<Item> {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.id == itemID })
        descriptor.includePendingChanges = false
        return descriptor
    }

    var body: some View {
        Group {
            if let error = _items.fetchError {
                ContentUnavailableView(
                    "個体を読み込めませんでした",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(error.localizedDescription) 一覧に戻って、もう一度個体を選んでください。")
                )
            } else {
                switch ItemDetailContent.resolve(candidates: items) {
                case .success(let detail):
                    details(detail)
                case .failure(.notFound):
                    ContentUnavailableView(
                        "個体が見つかりません",
                        systemImage: "shippingbox",
                        description: Text("在庫一覧に戻って、表示されている個体を選んでください。")
                    )
                case .failure(.duplicateID):
                    ContentUnavailableView(
                        "個体を特定できません",
                        systemImage: "exclamationmark.triangle",
                        description: Text("同じIDの個体が複数あります。在庫一覧に戻ってください。")
                    )
                }
            }
        }
        .onAppear {
            expirationReferenceDate = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            expirationReferenceDate = .now
        }
        .navigationTitle("個体詳細")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .editDates(let item):
                ItemDateEditor(item: item)
            case .open(let item):
                ItemOpeningForm { date, calendar in
                    open(item, on: date, calendar: calendar)
                }
            }
        }
    }

    private func details(_ detail: ItemDetailContent) -> some View {
        let expiration = detail.expirationPresentation(now: expirationReferenceDate)

        return Form {
            Section("個体情報") {
                LabeledContent("状態", value: detail.status)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("状態、\(detail.status)")
                    .accessibilityIdentifier("item-detail-status")
                LabeledContent("賞味期限") {
                    InventoryExpirationLabel(text: expiration.detailText, warningColor: expiration.warningColor)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("賞味期限、\(expiration.detailText)")
                .accessibilityIdentifier("item-detail-expiration")
                LabeledContent("開封日", value: detail.opening)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("開封日、\(detail.opening)")
                    .accessibilityIdentifier("item-detail-opening-date")
                if detail.item.status != nil {
                    Button("日付を編集") {
                        sheet = .editDates(detail.item)
                    }
                    .accessibilityIdentifier("item-detail-edit-dates")
                }
            }

            Section("商品情報") {
                LabeledContent("商品名", value: detail.product.name)
                LabeledContent("種類", value: detail.product.type)
            }

            Section {
                if detail.item.status == .unopened {
                    Button("この1本を開封") {
                        sheet = .open(detail.item)
                    }
                    .accessibilityIdentifier("item-detail-open")
                }
                if let deletionError {
                    Text(deletionError)
                        .foregroundStyle(.red)
                }
                if detail.canDeleteFromInventory {
                    Button("この1本を削除", role: .destructive) {
                        deletionError = nil
                        showsDeletionConfirmation = true
                    }
                }
            }
        }
        .alert("この1本を削除しますか？", isPresented: $showsDeletionConfirmation, presenting: detail) { target in
            Button("削除する", role: .destructive) { delete(target) }
            Button("キャンセル", role: .cancel) {}
        } message: { target in
            let expirationText = target.expirationPresentation(now: expirationReferenceDate).rowText
            Text("「\(target.product.name)」の\(target.status)の1本（\(expirationText)）を削除します。この操作は取り消せません。")
        }
    }

    private func isCurrent(_ item: Item) -> Bool {
        _items.fetchError == nil && items.count == 1 && items.first === item && !item.isDeleted
    }

    private func open(_ item: Item, on date: Date, calendar: Calendar) -> Result<Void, ItemActions.ActionError> {
        guard isCurrent(item) else {
            return .failure(.itemNotInContext)
        }

        return openingActions.open(item, openingDate: date, calendar: calendar)
    }

    private var openingActions: ItemActions {
        #if DEBUG
            if failsNextOpeningSave {
                return ItemActions(context: modelContext) { _ in
                    // 個体の変更後、実際の保存前に失敗させてロールバックと再試行を確認する。
                    failsNextOpeningSave = false
                    return .failure(OpeningUITestError.saveFailed)
                }
            }
        #endif

        return ItemActions(context: modelContext)
    }

    #if DEBUG
        private nonisolated enum OpeningUITestError: Error {
            case saveFailed
        }

        private static var requestsOpeningSaveFailure: Bool {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--ui-test-fail-first-opening-save"),
                let storeIndex = arguments.firstIndex(of: "--ui-test-store-id"),
                arguments.indices.contains(storeIndex + 1)
            else {
                return false
            }

            return UUID(uuidString: arguments[storeIndex + 1]) != nil
        }
    #endif

    private func delete(_ target: ItemDetailContent) {
        guard isCurrent(target.item), target.item.modelContext === modelContext, target.canDeleteFromInventory
        else {
            deletionError = "削除できる在庫が見つかりません。在庫一覧から選び直してください。"
            return
        }

        switch ItemActions(context: modelContext).delete(target.item, confirmed: true) {
        case .success:
            dismiss()
        case .failure(.pendingChanges):
            deletionError = "ほかの変更の保存が終わってから、もう一度削除してください。"
        case .failure(.persistence(let error)):
            deletionError = "削除を保存できませんでした。\(error.localizedDescription) もう一度削除してください。"
        case .failure:
            deletionError = "削除できませんでした。在庫一覧から選び直してください。"
        }
    }
}

struct ItemDetailContent {
    nonisolated enum Unavailable: Error, Equatable, Sendable {
        case notFound
        case duplicateID
    }

    fileprivate let item: Item
    let product: InventoryProductLabels
    let status: String
    let expirationDate: Date?
    let opening: String

    fileprivate var canDeleteFromInventory: Bool {
        item.status == .unopened || item.status == .inUse
    }

    func expirationPresentation(now: Date, calendar: Calendar = .current) -> InventoryExpirationPresentation {
        InventoryExpirationPresentation(expirationDate: expirationDate, now: now, calendar: calendar)
    }

    static func resolve(candidates: [Item]) -> Result<Self, Unavailable> {
        if candidates.count > 1 {
            return .failure(.duplicateID)
        }

        guard let item = candidates.first, !item.isDeleted, item.modelContext != nil else {
            return .failure(.notFound)
        }

        return .success(Self(item: item))
    }

    private init(item: Item) {
        self.item = item
        product = InventoryProductLabels(product: item.product)
        status = item.status?.displayName ?? "不明な状態"
        expirationDate = item.expirationDate
        opening = item.openingDate?.formatted(date: .abbreviated, time: .omitted) ?? "未設定"
    }
}

private struct ItemOpeningForm: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.dismiss) private var dismiss
    @State private var openingDate: Date
    @State private var latestOpeningDate: Date
    @State private var saveError: ItemActions.ActionError?

    private let confirm: @MainActor (Date, Calendar) -> Result<Void, ItemActions.ActionError>

    init(confirm: @escaping @MainActor (Date, Calendar) -> Result<Void, ItemActions.ActionError>) {
        let now = Date.now
        _openingDate = State(initialValue: now)
        _latestOpeningDate = State(initialValue: now)
        self.confirm = confirm
    }

    var body: some View {
        let recordedDate = openingDate.formatted(date: .abbreviated, time: .omitted)

        NavigationStack {
            Form {
                if let message = saveErrorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("item-open-error")
                    }
                }

                Section {
                    DatePicker("開封日", selection: $openingDate, in: ...latestOpeningDate, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .accessibilityIdentifier("item-open-date")
                } header: {
                    Text("開封日")
                } footer: {
                    Text("「\(recordedDate)」を開封日として記録し、状態を使用中に変更します。")
                        .accessibilityIdentifier("item-open-preview")
                }
            }
            .navigationTitle("この1本を開封")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .accessibilityIdentifier("item-open-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("開封する", action: save)
                        .accessibilityIdentifier("item-open-confirm")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            latestOpeningDate = .now
        }
    }

    private func save() {
        switch confirm(openingDate, calendar) {
        case .success:
            dismiss()
        case .failure(let error):
            saveError = error
        }
    }

    private var saveErrorMessage: String? {
        switch saveError {
        case nil:
            return nil
        case .itemNotInContext, .validation(.invalidTransition), .validation(.unknownCurrentStatus):
            return "開封できる個体が見つかりません。在庫一覧から選び直してください。"
        case .validation(.futureOpeningDate):
            return "開封日には今日以前の日付を選んでください。"
        case .pendingChanges:
            return "ほかの変更の保存が終わってから、もう一度「開封する」を押してください。"
        case .persistence:
            return "開封を保存できませんでした。日付を変えずにもう一度「開封する」を押せます。"
        case .productNotInContext, .deletionNotConfirmed, .validation:
            return "開封できませんでした。入力内容と個体の状態を確認してください。"
        }
    }
}

private struct ItemDateEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var state: ItemDateEditState

    private let item: Item

    init(item: Item) {
        self.item = item
        _state = State(initialValue: ItemDateEditState(item: item))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = state.saveErrorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("item-date-edit-error")
                    }
                }

                Section("賞味期限（任意）") {
                    Toggle("賞味期限を設定", isOn: $state.hasExpirationDate)
                        .accessibilityIdentifier("item-date-edit-has-expiration")
                    if state.hasExpirationDate {
                        DatePicker("賞味期限", selection: $state.expirationDate, displayedComponents: .date)
                            .accessibilityIdentifier("item-date-edit-expiration")
                    }
                }

                Section("開封日") {
                    if let openingDate = Binding($state.openingDate) {
                        DatePicker("開封日", selection: openingDate, displayedComponents: .date)
                            .accessibilityIdentifier("item-date-edit-opening")
                    } else {
                        Text("未開封の個体は開封日を編集できません。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("日付を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .accessibilityIdentifier("item-date-edit-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier("item-date-edit-save")
                }
            }
        }
    }

    private func save() {
        if case .success = state.save(item: item, using: ItemActions(context: modelContext)) {
            dismiss()
        }
    }
}

struct ItemDateEditState {
    var hasExpirationDate: Bool
    var expirationDate: Date
    var openingDate: Date?
    private var saveError: ItemActions.ActionError?

    init(item: Item, now: Date = .now) {
        hasExpirationDate = item.expirationDate != nil
        expirationDate = item.expirationDate ?? now
        switch item.status {
        case .inUse, .consumed:
            openingDate = item.openingDate ?? now
        case .unopened, nil:
            openingDate = nil
        }
    }

    mutating func save(
        item: Item, using actions: ItemActions, now: Date = .now, calendar: Calendar = .current
    ) -> Result<Void, ItemActions.ActionError> {
        guard !item.isDeleted else {
            saveError = .itemNotInContext
            return .failure(.itemNotInContext)
        }

        let result = actions.updateDates(
            item, expirationDate: hasExpirationDate ? expirationDate : nil, openingDate: openingDate,
            now: now, calendar: calendar
        )
        switch result {
        case .success:
            saveError = nil
        case .failure(let error):
            saveError = error
        }
        return result
    }

    var saveErrorMessage: String? {
        switch saveError {
        case nil:
            return nil
        case .validation(.futureOpeningDate):
            return "開封日に未来の日付は設定できません。今日以前の日付を選んでください。"
        case .validation(.consumedDateBeforeOpeningDate):
            return "開封日は使い切り日以前の日付を選んでください。"
        case .itemNotInContext:
            return "編集する個体が見つかりません。在庫一覧から選び直してください。"
        case .pendingChanges:
            return "ほかの変更の保存が終わってから、もう一度「保存」を押してください。"
        case .persistence:
            return "日付を保存できませんでした。もう一度「保存」を押してください。"
        case .productNotInContext, .deletionNotConfirmed, .validation:
            return "日付を保存できませんでした。入力内容と個体の状態を確認してください。"
        }
    }
}
