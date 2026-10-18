import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ItemActionsTests {
    private let originalDate = Date(timeIntervalSince1970: 1_600_000_000)
    private let registrationDate = Date(timeIntervalSince1970: 1_750_000_123)
    private let expirationDate = Date(timeIntervalSince1970: 1_800_000_321)
    private let originalImage = Data([0, 1, 2, 255])

    nonisolated private enum StoreError: Error, Equatable {
        case unavailable
    }

    @Test(arguments: [nil, Date(timeIntervalSince1970: 1_700_000_123), Date(timeIntervalSince1970: 1_800_000_321)])
    func registrationPreservesOptionalPastAndFutureExpirationDates(_ expiration: Date?) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)

        let item = try ItemActions(context: context).create(
            for: product, expirationDate: expiration, now: registrationDate
        ).get()

        #expect(item.id != product.id)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectNewValues(item, expiration: expiration)
        expectProductValues(product)
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1)

        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Item>()).first)
        #expect(saved.id == item.id)
        #expect(saved.product?.id == product.id)
        expectNewValues(saved, expiration: expiration)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 1)
    }

    @Test func repeatedRegistrationCreatesOneDistinctItemPerSaveAndPreservesExistingData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let existing = makeExistingItem(product: product)
        context.insert(existing)
        try context.save()
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        let first = try actions.create(for: product, now: registrationDate).get()

        #expect(saveCalls == 1)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 2)
        #expect(first.id != existing.id)
        #expect(first.product === product)
        expectNewValues(first, expiration: nil)

        let second = try actions.create(
            for: product, expirationDate: expirationDate, now: registrationDate
        ).get()

        #expect(saveCalls == 2)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 3)
        #expect(Set([existing.id, first.id, second.id]).count == 3)
        #expect(second.product === product)
        expectNewValues(second, expiration: expirationDate)
        expectExistingValues(existing)
        #expect(existing.product === product)
        #expect(Set((product.items ?? []).map(\.id)) == Set([existing.id, first.id, second.id]))
        expectProductValues(product)
        expectProductValues(other, name: "みそ")
        #expect((other.items ?? []).isEmpty)
        #expect(!context.hasChanges)

        let reader = ModelContext(container)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        let savedProduct = try #require(products.first { $0.id == product.id })
        let savedOther = try #require(products.first { $0.id == other.id })
        expectProductValues(savedProduct)
        expectProductValues(savedOther, name: "みそ")
        #expect((savedOther.items ?? []).isEmpty)
        #expect(Set((savedProduct.items ?? []).map(\.id)) == Set([existing.id, first.id, second.id]))
        let savedItems = try reader.fetch(FetchDescriptor<Item>())
        #expect(savedItems.count == 3)
        expectExistingValues(try #require(savedItems.first { $0.id == existing.id }))
    }

    @Test func registrationSurvivesReopeningStoreWithProductRelationship() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("items.store")
        var productID: UUID?
        var itemID: UUID?

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try makeSavedProduct(in: context)
            let item = try ItemActions(context: context).create(
                for: product, expirationDate: expirationDate, now: registrationDate
            ).get()
            productID = product.id
            itemID = item.id
            #expect(!context.hasChanges)
        }

        let reopened = try makeContainer(at: url)
        let reader = ModelContext(reopened)
        let products = try reader.fetch(FetchDescriptor<Product>())
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(products.count == 1)
        #expect(items.count == 1)
        let product = try #require(products.first)
        let item = try #require(items.first)
        #expect(product.id == productID)
        #expect(item.id == itemID)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectProductValues(product)
        expectNewValues(item, expiration: expirationDate)
    }

    @Test func unmanagedAndOtherContextProductsAreRejectedWithoutSaving() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let owner = ModelContext(container)
        let saved = try makeSavedProduct(in: owner)
        let unmanaged = Product(name: "未登録", type: "調味料", updatedAt: originalDate)
        let unmanagedID = unmanaged.id
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.productNotInContext) = actions.create(for: unmanaged) else {
            Issue.record("未管理の商品が拒否されなかった")
            return
        }
        guard case .failure(.productNotInContext) = actions.create(for: saved) else {
            Issue.record("別contextの商品が拒否されなかった")
            return
        }

        #expect(saveCalls == 0)
        #expect(unmanaged.id == unmanagedID)
        #expect(unmanaged.name == "未登録")
        #expect(unmanaged.type == "調味料")
        #expect(unmanaged.updatedAt == originalDate)
        #expect(unmanaged.modelContext == nil)
        #expect((unmanaged.items ?? []).isEmpty)
        expectProductValues(saved)
        #expect(saved.modelContext === owner)
        #expect((saved.items ?? []).isEmpty)
        #expect(!context.hasChanges)
        #expect(!owner.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<Product>()) == 1)
        expectProductValues(try #require(reader.fetch(FetchDescriptor<Product>()).first))
    }

    @Test func unsavedProductIsRejectedWithoutSavingOrRollingBackInput() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let pending = Product(name: "未保存", type: "調味料", updatedAt: originalDate)
        let productID = pending.id
        context.insert(pending)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.pendingChanges) = actions.create(for: pending) else {
            Issue.record("未保存の商品が拒否されなかった")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        #expect(pending.modelContext === context)
        #expect(pending.id == productID)
        #expect(pending.name == "未保存")
        #expect(pending.type == "調味料")
        #expect(pending.updatedAt == originalDate)
        #expect((pending.items ?? []).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Product>()) == 1)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect(try reader.fetchCount(FetchDescriptor<Product>()) == 0)
    }

    @Test func unrelatedPendingEditsAreNeitherSavedNorRolledBack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        other.name = "編集中のみそ"
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.pendingChanges) = actions.create(for: product) else {
            Issue.record("無関係な未保存変更があるcontextで登録された")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        expectProductValues(product)
        expectProductValues(other, name: "編集中のみそ")
        #expect((product.items ?? []).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        expectProductValues(try #require(products.first { $0.id == product.id }))
        expectProductValues(try #require(products.first { $0.id == other.id }), name: "みそ")
    }

    @Test func failedRegistrationRestoresRelationshipsAndRetryCreatesOnlyOneItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let productID = product.id
        let existing = makeExistingItem(product: product)
        let existingID = existing.id
        context.insert(existing)
        try context.save()
        var saveCalls = 0
        let failing = ItemActions(context: context) { _ in
            saveCalls += 1
            return .failure(StoreError.unavailable)
        }

        let result = failing.create(for: product, expirationDate: expirationDate, now: registrationDate)

        guard case .failure(.persistence(let error)) = result else {
            Issue.record("元の保存エラーが返されなかった")
            return
        }
        #expect(error as? StoreError == .unavailable)
        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        #expect(product.id == productID)
        expectProductValues(product)
        #expect(existing.id == existingID)
        #expect(existing.product === product)
        expectExistingValues(existing)
        #expect(product.items?.map(\.id) == [existingID])
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 1)

        do {
            let reader = ModelContext(container)
            let savedProduct = try #require(reader.fetch(FetchDescriptor<Product>()).first)
            let savedItems = try reader.fetch(FetchDescriptor<Item>())
            #expect(savedProduct.id == productID)
            expectProductValues(savedProduct)
            #expect(savedItems.count == 1)
            let savedItem = try #require(savedItems.first)
            #expect(savedItem.id == existingID)
            #expect(savedItem.product === savedProduct)
            #expect(savedProduct.items?.map(\.id) == [existingID])
            expectExistingValues(savedItem)
        }

        // 同じ商品と入力をそのまま再試行しても、失敗時の個体は重複しない。
        let retried = try ItemActions(context: context).create(
            for: product, expirationDate: expirationDate, now: registrationDate
        ).get()

        #expect(retried.product === product)
        #expect(retried.id != existingID)
        expectNewValues(retried, expiration: expirationDate)
        #expect(!context.hasChanges)
        #expect(Set((product.items ?? []).map(\.id)) == Set([existingID, retried.id]))
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 2)
        let reader = ModelContext(container)
        let savedItems = try reader.fetch(FetchDescriptor<Item>())
        #expect(savedItems.count == 2)
        let saved = try #require(savedItems.first { $0.id == retried.id })
        #expect(saved.product?.id == productID)
        expectNewValues(saved, expiration: expirationDate)
        expectExistingValues(try #require(savedItems.first { $0.id == existingID }))
    }

    @Test(
        arguments: [ItemStatus.unopened, .inUse, .consumed],
        [nil, Date(timeIntervalSince1970: 1_500_000_000), Date(timeIntervalSince1970: 1_800_000_321)] as [Date?]
    )
    func dateEditingSavesOnlyTheSelectedItemOnce(_ status: ItemStatus, _ expiration: Date?) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let otherProduct = try makeSavedProduct(in: context, name: "みそ")
        let item = try makeSavedItem(in: context, product: product, status: status)
        let sameProductItem = makeExistingItem(product: product)
        let otherProductItem = makeExistingItem(product: otherProduct)
        context.insert(sameProductItem)
        context.insert(otherProductItem)
        try context.save()
        let original = ItemSnapshot(item)
        let sameProductSnapshot = ItemSnapshot(sameProductItem)
        let otherProductSnapshot = ItemSnapshot(otherProductItem)
        let opening = item.openingDate.map { $0.addingTimeInterval(86_400) }
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        try actions.updateDates(
            item, expirationDate: expiration, openingDate: opening, now: registrationDate
        ).get()

        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        #expect(item.id == original.id)
        #expect(item.product === product)
        #expect(item.statusRawValue == original.statusRawValue)
        #expect(item.consumedDate == original.consumedDate)
        expectEditedDates(item, expiration: expiration, opening: opening)
        #expect(ItemSnapshot(sameProductItem) == sameProductSnapshot)
        #expect(ItemSnapshot(otherProductItem) == otherProductSnapshot)
        expectProductValues(product)
        expectProductValues(otherProduct, name: "みそ")
        #expect(Set((product.items ?? []).map(\.id)) == Set([item.id, sameProductItem.id]))
        #expect(otherProduct.items?.map(\.id) == [otherProductItem.id])

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 3)
        let saved = try #require(items.first { $0.id == item.id })
        #expect(ItemSnapshot(saved) == ItemSnapshot(item))
        #expect(ItemSnapshot(try #require(items.first { $0.id == sameProductItem.id })) == sameProductSnapshot)
        #expect(ItemSnapshot(try #require(items.first { $0.id == otherProductItem.id })) == otherProductSnapshot)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        expectProductValues(try #require(products.first { $0.id == product.id }))
        expectProductValues(try #require(products.first { $0.id == otherProduct.id }), name: "みそ")
    }

    @Test(
        arguments: [
            ("inUse", Date(timeIntervalSince1970: 1_750_100_123), ItemRules.ValidationError.futureOpeningDate),
            ("inUse", nil, .openingDateRequired),
            ("unopened", Date(timeIntervalSince1970: 1_600_000_000), .unexpectedOpeningDate),
            ("consumed", Date(timeIntervalSince1970: 1_600_259_200), .consumedDateBeforeOpeningDate),
            ("futureStatus", nil, .unknownCurrentStatus),
        ] as [(String, Date?, ItemRules.ValidationError)]
    )
    func rejectedDateInputDoesNotSaveOrChangeFields(
        _ input: (status: String, opening: Date?, error: ItemRules.ValidationError)
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(
            in: context, product: product, status: ItemStatus(rawValue: input.status) ?? .unopened
        )
        item.statusRawValue = input.status
        try context.save()
        let original = ItemSnapshot(item)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        let result = actions.updateDates(
            item, expirationDate: expirationDate, openingDate: input.opening,
            now: registrationDate, calendar: try calendar(secondsFromGMT: 0)
        )

        guard case .failure(.validation(let error)) = result else {
            Issue.record("日付入力の検証エラーが返されなかった")
            return
        }
        #expect(error == input.error)
        #expect(saveCalls == 0)
        #expect(!context.hasChanges)
        #expect(ItemSnapshot(item) == original)
        expectProductValues(product)
        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Item>()).first)
        #expect(ItemSnapshot(saved) == original)
    }

    @Test func dateEditingRejectsUnmanagedAndOtherContextItemsWithoutChangingThem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let owner = ModelContext(container)
        let product = try makeSavedProduct(in: owner)
        let saved = try makeSavedItem(in: owner, product: product)
        let unmanaged = makeExistingItem(product: Product(name: "未登録", type: "調味料"))
        let savedSnapshot = ItemSnapshot(saved)
        let unmanagedSnapshot = ItemSnapshot(unmanaged)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard
            case .failure(.itemNotInContext) = actions.updateDates(
                unmanaged, expirationDate: expirationDate, openingDate: originalDate, now: registrationDate
            )
        else {
            Issue.record("未管理の個体が拒否されなかった")
            return
        }
        guard
            case .failure(.itemNotInContext) = actions.updateDates(
                saved, expirationDate: expirationDate, openingDate: originalDate, now: registrationDate
            )
        else {
            Issue.record("別contextの個体が拒否されなかった")
            return
        }

        #expect(saveCalls == 0)
        #expect(ItemSnapshot(unmanaged) == unmanagedSnapshot)
        #expect(ItemSnapshot(saved) == savedSnapshot)
        #expect(unmanaged.modelContext == nil)
        #expect(saved.modelContext === owner)
        #expect(!context.hasChanges)
        #expect(!owner.hasChanges)
        expectProductValues(product)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 1)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == savedSnapshot)
    }

    private enum PendingEdit: CaseIterable {
        case item
        case unrelatedProduct
        case insertedItem
    }

    @Test(arguments: PendingEdit.allCases)
    private func dateEditingPreservesPendingChangesWithoutSavingOrRollingBack(_ pendingEdit: PendingEdit) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let savedItem = try makeSavedItem(in: context, product: product)
        let savedSnapshot = ItemSnapshot(savedItem)
        let target: Item
        switch pendingEdit {
        case .item:
            target = savedItem
            target.expirationDate = expirationDate
        case .unrelatedProduct:
            target = savedItem
            other.name = "編集中のみそ"
        case .insertedItem:
            target = makeExistingItem(product: product)
            context.insert(target)
        }
        let pendingSnapshot = ItemSnapshot(target)
        let pendingName = other.name
        let pendingIDs = Set((product.items ?? []).map(\.id))
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard
            case .failure(.pendingChanges) = actions.updateDates(
                target, expirationDate: nil, openingDate: originalDate, now: registrationDate
            )
        else {
            Issue.record("未保存変更があるcontextで日付が編集された")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        #expect(ItemSnapshot(target) == pendingSnapshot)
        #expect(target.modelContext === context)
        #expect(Set((product.items ?? []).map(\.id)) == pendingIDs)
        expectProductValues(other, name: pendingName)
        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(ItemSnapshot(try #require(items.first)) == savedSnapshot)
        let products = try reader.fetch(FetchDescriptor<Product>())
        expectProductValues(try #require(products.first { $0.id == other.id }), name: "みそ")
    }

    @Test func failedDateSaveRestoresAllFieldsAndRelationshipsBeforeRetry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product, status: .consumed)
        let sibling = makeExistingItem(product: product)
        context.insert(sibling)
        try context.save()
        let original = ItemSnapshot(item)
        let siblingSnapshot = ItemSnapshot(sibling)
        let opening = originalDate.addingTimeInterval(86_400)
        var saveCalls = 0
        let failing = ItemActions(context: context) { _ in
            saveCalls += 1
            return .failure(StoreError.unavailable)
        }

        let result = failing.updateDates(
            item, expirationDate: expirationDate, openingDate: opening, now: registrationDate
        )

        guard case .failure(.persistence(let error)) = result else {
            Issue.record("元の日付保存エラーが返されなかった")
            return
        }
        #expect(error as? StoreError == .unavailable)
        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        #expect(ItemSnapshot(item) == original)
        #expect(item.product === product)
        #expect(ItemSnapshot(sibling) == siblingSnapshot)
        #expect(Set((product.items ?? []).map(\.id)) == Set([item.id, sibling.id]))
        expectProductValues(product)
        let failedReader = ModelContext(container)
        let failedItems = try failedReader.fetch(FetchDescriptor<Item>())
        #expect(ItemSnapshot(try #require(failedItems.first { $0.id == item.id })) == original)

        // draftの日付はモデルへ事前反映せず、同じ入力をそのまま再試行できる。
        try ItemActions(context: context).updateDates(
            item, expirationDate: expirationDate, openingDate: opening, now: registrationDate
        ).get()

        #expect(!context.hasChanges)
        expectEditedDates(item, expiration: expirationDate, opening: opening)
        #expect(item.id == original.id)
        #expect(item.statusRawValue == original.statusRawValue)
        #expect(item.consumedDate == original.consumedDate)
        #expect(item.product === product)
        #expect(ItemSnapshot(sibling) == siblingSnapshot)
        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 2)
        #expect(ItemSnapshot(try #require(items.first { $0.id == item.id })) == ItemSnapshot(item))
        #expect(ItemSnapshot(try #require(items.first { $0.id == sibling.id })) == siblingSnapshot)
    }

    @Test func dateEditingUsesTheInjectedCalendarAtTheDayBoundary() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product)
        let original = ItemSnapshot(item)
        let now = Date(timeIntervalSince1970: 1_736_006_400)  // 2025-01-04 16:00 UTC
        let opening = now.addingTimeInterval(9 * 3600)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard
            case .failure(.validation(.futureOpeningDate)) = actions.updateDates(
                item, expirationDate: nil, openingDate: opening, now: now, calendar: try calendar(secondsFromGMT: 0)
            )
        else {
            Issue.record("UTCの翌日の開封日が拒否されなかった")
            return
        }
        #expect(saveCalls == 0)
        #expect(ItemSnapshot(item) == original)
        #expect(!context.hasChanges)

        try actions.updateDates(
            item, expirationDate: nil, openingDate: opening, now: now,
            calendar: try calendar(secondsFromGMT: 9 * 3600)
        ).get()

        #expect(saveCalls == 1)
        #expect(item.openingDate == opening)
        #expect(item.expirationDate == nil)
        #expect(item.updatedAt == now)
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == ItemSnapshot(item))
    }

    @Test func editedDatesSurviveReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("edited-items.store")
        let opening = originalDate.addingTimeInterval(86_400)
        let expected: ItemSnapshot

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try makeSavedProduct(in: context)
            let item = try makeSavedItem(in: context, product: product, status: .consumed)
            try ItemActions(context: context).updateDates(
                item, expirationDate: nil, openingDate: opening, now: registrationDate
            ).get()
            expected = ItemSnapshot(item)
            #expect(!context.hasChanges)
        }

        let reopened = try makeContainer(at: url)
        let reader = ModelContext(reopened)
        let items = try reader.fetch(FetchDescriptor<Item>())
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(items.count == 1)
        #expect(products.count == 1)
        let item = try #require(items.first)
        let product = try #require(products.first)
        #expect(ItemSnapshot(item) == expected)
        expectEditedDates(item, expiration: nil, opening: opening)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectProductValues(product)
    }

    private enum StatusTransition: CaseIterable {
        case open
        case consume

        var source: ItemStatus {
            switch self {
            case .open:
                return .unopened
            case .consume:
                return .inUse
            }
        }

        var destination: ItemStatus {
            switch self {
            case .open:
                return .inUse
            case .consume:
                return .consumed
            }
        }

        @MainActor
        func apply(
            _ actions: ItemActions, to item: Item, date: Date, now: Date, calendar: Calendar = .current
        ) -> Result<Void, ItemActions.ActionError> {
            switch self {
            case .open:
                return actions.open(item, openingDate: date, now: now, calendar: calendar)
            case .consume:
                return actions.consume(item, consumedDate: date, now: now, calendar: calendar)
            }
        }
    }

    @Test(arguments: StatusTransition.allCases)
    private func statusTransitionSavesConfirmedDateAndStatusTogetherOnce(_ transition: StatusTransition) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let otherProduct = try makeSavedProduct(in: context, name: "みそ")
        let item = try makeSavedItem(in: context, product: product, status: transition.source)
        let sibling = try makeSavedItem(in: context, product: product)
        let otherItem = try makeSavedItem(in: context, product: otherProduct)
        let original = ItemSnapshot(item)
        let siblingSnapshot = ItemSnapshot(sibling)
        let otherSnapshot = ItemSnapshot(otherItem)
        let confirmedDate = originalDate.addingTimeInterval(86_400)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            // 保存を呼ぶ時点で、確認済み日付と状態が同時に反映されている。
            self.expectTransitionedValues(
                item, original: original, transition: transition, confirmedDate: confirmedDate
            )
            #expect(item.product === product)
            #expect(ItemSnapshot(sibling) == siblingSnapshot)
            #expect(ItemSnapshot(otherItem) == otherSnapshot)
            return Result { try context.save() }
        }

        try transition.apply(actions, to: item, date: confirmedDate, now: registrationDate).get()

        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        expectTransitionedValues(item, original: original, transition: transition, confirmedDate: confirmedDate)
        #expect(ItemSnapshot(sibling) == siblingSnapshot)
        #expect(ItemSnapshot(otherItem) == otherSnapshot)
        #expect(Set((product.items ?? []).map(\.id)) == Set([item.id, sibling.id]))
        #expect(otherProduct.items?.map(\.id) == [otherItem.id])
        expectProductValues(product)
        expectProductValues(otherProduct, name: "みそ")

        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 3)
        let saved = try #require(items.first { $0.id == item.id })
        #expect(ItemSnapshot(saved) == ItemSnapshot(item))
        #expect(ItemSnapshot(try #require(items.first { $0.id == sibling.id })) == siblingSnapshot)
        #expect(ItemSnapshot(try #require(items.first { $0.id == otherItem.id })) == otherSnapshot)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        let savedProduct = try #require(products.first { $0.id == product.id })
        let savedOther = try #require(products.first { $0.id == otherProduct.id })
        #expect(saved.product === savedProduct)
        #expect(Set((savedProduct.items ?? []).map(\.id)) == Set([item.id, sibling.id]))
        #expect(savedOther.items?.map(\.id) == [otherItem.id])
        expectProductValues(savedProduct)
        expectProductValues(savedOther, name: "みそ")
    }

    @Test(
        arguments: [
            (StatusTransition.open, "inUse", ItemRules.ValidationError.invalidTransition),
            (.open, "consumed", .invalidTransition),
            (.consume, "unopened", .invalidTransition),
            (.consume, "consumed", .invalidTransition),
            (.open, "futureStatus", .unknownCurrentStatus),
            (.consume, "futureStatus", .unknownCurrentStatus),
        ] as [(StatusTransition, String, ItemRules.ValidationError)]
    )
    private func statusTransitionRejectsInvalidSourcesWithoutChangingSavedValues(
        _ input: (transition: StatusTransition, status: String, error: ItemRules.ValidationError)
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product, status: input.transition.source)
        item.statusRawValue = input.status
        try context.save()
        let original = ItemSnapshot(item)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        let result = input.transition.apply(actions, to: item, date: originalDate, now: registrationDate)

        guard case .failure(.validation(let error)) = result else {
            Issue.record("重複操作・飛び越し・逆向き・未知の状態が拒否されなかった")
            return
        }
        #expect(error == input.error)
        #expect(saveCalls == 0)
        #expect(!context.hasChanges)
        #expect(ItemSnapshot(item) == original)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectProductValues(product)
        let reader = ModelContext(container)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == original)
    }

    @Test(
        arguments: [
            (
                StatusTransition.open, nil, nil, Date(timeIntervalSince1970: 1_750_100_123),
                ItemRules.ValidationError.futureOpeningDate
            ),
            (
                .open, nil, Date(timeIntervalSince1970: 1_600_000_000), Date(timeIntervalSince1970: 1_600_086_400),
                .unexpectedConsumedDate
            ),
            (.consume, nil, nil, Date(timeIntervalSince1970: 1_600_086_400), .openingDateRequired),
            (
                .consume, Date(timeIntervalSince1970: 1_600_000_000), nil, Date(timeIntervalSince1970: 1_599_913_600),
                .consumedDateBeforeOpeningDate
            ),
            (
                .consume, Date(timeIntervalSince1970: 1_750_100_123), nil, Date(timeIntervalSince1970: 1_750_186_523),
                .futureOpeningDate
            ),
        ] as [(StatusTransition, Date?, Date?, Date, ItemRules.ValidationError)]
    )
    private func statusTransitionValidatesDatesBeforeMutatingOrSaving(
        _ input: (
            transition: StatusTransition, opening: Date?, consumed: Date?, confirmed: Date,
            error: ItemRules.ValidationError
        )
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product, status: input.transition.source)
        item.openingDate = input.opening
        item.consumedDate = input.consumed
        try context.save()
        let original = ItemSnapshot(item)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        let result = input.transition.apply(
            actions, to: item, date: input.confirmed, now: registrationDate, calendar: try calendar(secondsFromGMT: 0)
        )

        guard case .failure(.validation(let error)) = result else {
            Issue.record("不正な日付を持つ状態遷移が拒否されなかった")
            return
        }
        #expect(error == input.error)
        #expect(saveCalls == 0)
        #expect(!context.hasChanges)
        #expect(ItemSnapshot(item) == original)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectProductValues(product)
        let reader = ModelContext(container)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == original)
    }

    @Test(arguments: StatusTransition.allCases)
    private func statusTransitionRejectsUnmanagedAndForeignItems(_ transition: StatusTransition) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let owner = ModelContext(container)
        let product = try makeSavedProduct(in: owner)
        let saved = try makeSavedItem(in: owner, product: product, status: transition.source)
        let unmanaged = Item(product: Product(name: "未登録", type: "調味料"), status: transition.source)
        let savedSnapshot = ItemSnapshot(saved)
        let unmanagedSnapshot = ItemSnapshot(unmanaged)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        for item in [unmanaged, saved] {
            guard
                case .failure(.itemNotInContext) = transition.apply(
                    actions, to: item, date: originalDate, now: registrationDate
                )
            else {
                Issue.record("未管理または別contextの個体が拒否されなかった")
                return
            }
        }

        #expect(saveCalls == 0)
        #expect(ItemSnapshot(saved) == savedSnapshot)
        #expect(ItemSnapshot(unmanaged) == unmanagedSnapshot)
        #expect(saved.modelContext === owner)
        #expect(unmanaged.modelContext == nil)
        #expect(!context.hasChanges)
        #expect(!owner.hasChanges)
        #expect(product.items?.map(\.id) == [saved.id])
        expectProductValues(product)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 1)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == savedSnapshot)
    }

    @Test(arguments: StatusTransition.allCases, PendingEdit.allCases)
    private func statusTransitionPreservesPendingChanges(
        _ transition: StatusTransition, _ pendingEdit: PendingEdit
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let savedItem = try makeSavedItem(in: context, product: product, status: transition.source)
        let savedSnapshot = ItemSnapshot(savedItem)
        let target: Item
        switch pendingEdit {
        case .item:
            target = savedItem
            target.statusRawValue = "futureStatus"
        case .unrelatedProduct:
            target = savedItem
            other.name = "編集中のみそ"
        case .insertedItem:
            target = Item(product: product, status: transition.source, updatedAt: originalDate)
            context.insert(target)
        }
        let pendingSnapshot = ItemSnapshot(target)
        let pendingName = other.name
        let pendingIDs = Set((product.items ?? []).map(\.id))
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard
            case .failure(.pendingChanges) = transition.apply(
                actions, to: target, date: originalDate, now: registrationDate
            )
        else {
            Issue.record("未保存変更を持つcontextで状態が変更された")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        #expect(ItemSnapshot(target) == pendingSnapshot)
        #expect(target.modelContext === context)
        #expect(Set((product.items ?? []).map(\.id)) == pendingIDs)
        expectProductValues(other, name: pendingName)
        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(ItemSnapshot(try #require(items.first)) == savedSnapshot)
        let products = try reader.fetch(FetchDescriptor<Product>())
        expectProductValues(try #require(products.first { $0.id == other.id }), name: "みそ")
    }

    @Test(arguments: StatusTransition.allCases)
    private func failedStatusSaveRestoresFieldsAndRelationshipsForTheSameInputRetry(
        _ transition: StatusTransition
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product, status: transition.source)
        let sibling = try makeSavedItem(in: context, product: product)
        let original = ItemSnapshot(item)
        let siblingSnapshot = ItemSnapshot(sibling)
        let confirmedDate = originalDate.addingTimeInterval(86_400)
        var saveCalls = 0
        var shouldFail = true
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            self.expectTransitionedValues(
                item, original: original, transition: transition, confirmedDate: confirmedDate
            )
            if shouldFail {
                return .failure(StoreError.unavailable)
            }

            return Result { try context.save() }
        }

        let result = transition.apply(actions, to: item, date: confirmedDate, now: registrationDate)

        guard case .failure(.persistence(let error)) = result else {
            Issue.record("状態変更の元の保存エラーが返されなかった")
            return
        }
        #expect(error as? StoreError == .unavailable)
        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        #expect(ItemSnapshot(item) == original)
        #expect(ItemSnapshot(sibling) == siblingSnapshot)
        #expect(item.product === product)
        #expect(sibling.product === product)
        #expect(Set((product.items ?? []).map(\.id)) == Set([item.id, sibling.id]))
        expectProductValues(product)
        let failedReader = ModelContext(container)
        let failedItems = try failedReader.fetch(FetchDescriptor<Item>())
        #expect(failedItems.count == 2)
        #expect(ItemSnapshot(try #require(failedItems.first { $0.id == item.id })) == original)
        #expect(ItemSnapshot(try #require(failedItems.first { $0.id == sibling.id })) == siblingSnapshot)
        let failedProduct = try #require(failedReader.fetch(FetchDescriptor<Product>()).first)
        #expect(Set((failedProduct.items ?? []).map(\.id)) == Set([item.id, sibling.id]))
        expectProductValues(failedProduct)

        // 確認済み日付を変えず、同じ操作を保存失敗後に再試行できる。
        shouldFail = false
        try transition.apply(actions, to: item, date: confirmedDate, now: registrationDate).get()

        #expect(saveCalls == 2)
        #expect(!context.hasChanges)
        expectTransitionedValues(item, original: original, transition: transition, confirmedDate: confirmedDate)
        #expect(ItemSnapshot(sibling) == siblingSnapshot)
        #expect(item.product === product)
        #expect(Set((product.items ?? []).map(\.id)) == Set([item.id, sibling.id]))
        expectProductValues(product)
        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 2)
        #expect(ItemSnapshot(try #require(items.first { $0.id == item.id })) == ItemSnapshot(item))
        #expect(ItemSnapshot(try #require(items.first { $0.id == sibling.id })) == siblingSnapshot)
    }

    @Test func openingUsesTheInjectedLocalDayAndPreservesTheConfirmedTime() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product, status: .unopened)
        let original = ItemSnapshot(item)
        let now = Date(timeIntervalSince1970: 1_736_006_400)
        let opening = now.addingTimeInterval(9 * 3600)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard
            case .failure(.validation(.futureOpeningDate)) = actions.open(
                item, openingDate: opening, now: now, calendar: try calendar(secondsFromGMT: 0)
            )
        else {
            Issue.record("UTCの翌日の開封が拒否されなかった")
            return
        }
        #expect(saveCalls == 0)
        #expect(ItemSnapshot(item) == original)
        #expect(!context.hasChanges)

        // 日本では同じ暦日なので、現在時刻より後の確認済み時刻もそのまま保存する。
        try actions.open(
            item, openingDate: opening, now: now, calendar: try calendar(secondsFromGMT: 9 * 3600)
        ).get()

        #expect(saveCalls == 1)
        #expect(item.status == .inUse)
        #expect(item.openingDate == opening)
        #expect(item.consumedDate == nil)
        #expect(item.updatedAt == now)
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == ItemSnapshot(item))
    }

    @Test func consumingUsesTheInjectedLocalDayInsteadOfTheOrderOfTimes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product)
        let opening = Date(timeIntervalSince1970: 1_736_006_400)
        let consumed = opening.addingTimeInterval(-2 * 3600)
        item.openingDate = opening
        try context.save()
        let original = ItemSnapshot(item)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard
            case .failure(.validation(.consumedDateBeforeOpeningDate)) = actions.consume(
                item, consumedDate: consumed, now: registrationDate, calendar: try calendar(secondsFromGMT: 9 * 3600)
            )
        else {
            Issue.record("日本で開封日の前日になる使い切りが拒否されなかった")
            return
        }
        #expect(saveCalls == 0)
        #expect(ItemSnapshot(item) == original)
        #expect(!context.hasChanges)

        // UTCでは同じ暦日なので、開封時刻より前の使い切り時刻も許可する。
        try actions.consume(
            item, consumedDate: consumed, now: registrationDate, calendar: try calendar(secondsFromGMT: 0)
        ).get()

        #expect(saveCalls == 1)
        #expect(item.status == .consumed)
        #expect(item.openingDate == opening)
        #expect(item.consumedDate == consumed)
        #expect(item.updatedAt == registrationDate)
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == ItemSnapshot(item))
    }

    @Test func consumingAllowsAFutureConfirmedDateUnderTheCurrentSpecification() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product)
        let original = ItemSnapshot(item)
        let future = registrationDate.addingTimeInterval(86_400)

        try ItemActions(context: context).consume(item, consumedDate: future, now: registrationDate).get()

        expectTransitionedValues(item, original: original, transition: .consume, confirmedDate: future)
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        #expect(ItemSnapshot(try #require(reader.fetch(FetchDescriptor<Item>()).first)) == ItemSnapshot(item))
    }

    @Test(arguments: StatusTransition.allCases)
    private func statusTransitionsSurviveReopeningTheStore(_ transition: StatusTransition) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("transitioned-items.store")
        let confirmedDate = originalDate.addingTimeInterval(86_400)
        let expected: ItemSnapshot

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try makeSavedProduct(in: context)
            let item = try makeSavedItem(in: context, product: product, status: transition.source)
            try transition.apply(
                ItemActions(context: context), to: item, date: confirmedDate, now: registrationDate
            ).get()
            expected = ItemSnapshot(item)
            #expect(!context.hasChanges)
        }

        let reopened = try makeContainer(at: url)
        let reader = ModelContext(reopened)
        let items = try reader.fetch(FetchDescriptor<Item>())
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(items.count == 1)
        #expect(products.count == 1)
        let item = try #require(items.first)
        let product = try #require(products.first)
        #expect(ItemSnapshot(item) == expected)
        #expect(item.status == transition.destination)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [item.id])
        expectProductValues(product)
    }

    @Test(arguments: ItemStatus.allCases)
    func confirmedDeletionRemovesOnlyTheSelectedIDAndPreservesAllSurvivors(_ status: ItemStatus) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let item = try makeSavedItem(in: context, product: product, status: status)
        let deletedID = item.id
        let productID = product.id
        let otherID = other.id
        let siblings = try ItemStatus.allCases.map { try makeSavedItem(in: context, product: product, status: $0) }
        let siblingSnapshots = siblings.map(ItemSnapshot.init)
        let otherItem = try makeSavedItem(in: context, product: other, status: .consumed)
        let otherSnapshot = ItemSnapshot(otherItem)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        try actions.delete(item, confirmed: true).get()

        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        // 保存済みの削除対象には触れず、削除前に控えたIDと残った個体で確認する。
        #expect(try context.fetch(FetchDescriptor<Item>()).allSatisfy { $0.id != deletedID })
        try expectInventory(
            in: context, productID: productID, items: siblingSnapshots,
            otherProductID: otherID, otherItems: [otherSnapshot]
        )
        try expectInventory(
            in: ModelContext(container), productID: productID, items: siblingSnapshots,
            otherProductID: otherID, otherItems: [otherSnapshot]
        )
    }

    @Test(arguments: ItemStatus.allCases)
    func unconfirmedDeletionLeavesEverySavedValueAndRelationshipUntouched(_ status: ItemStatus) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let item = try makeSavedItem(in: context, product: product, status: status)
        let sibling = try makeSavedItem(in: context, product: product, status: .consumed)
        let snapshots = [ItemSnapshot(item), ItemSnapshot(sibling)]
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.deletionNotConfirmed) = actions.delete(item, confirmed: false) else {
            Issue.record("確認前の個体削除が拒否されなかった")
            return
        }

        #expect(saveCalls == 0)
        #expect(!context.hasChanges)
        #expect(item.modelContext === context)
        try expectInventory(
            in: context, productID: product.id, items: snapshots, otherProductID: other.id, otherItems: []
        )
        try expectInventory(
            in: ModelContext(container), productID: product.id, items: snapshots,
            otherProductID: other.id, otherItems: []
        )
    }

    @Test(arguments: ItemStatus.allCases)
    func failedDeletionRestoresTheSameObjectAndRelationshipsBeforeRetry(_ status: ItemStatus) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let item = try makeSavedItem(in: context, product: product, status: status)
        let original = ItemSnapshot(item)
        let productID = product.id
        let otherID = other.id
        let sibling = try makeSavedItem(in: context, product: product, status: .consumed)
        let siblingSnapshot = ItemSnapshot(sibling)
        let otherItem = try makeSavedItem(in: context, product: other)
        let otherSnapshot = ItemSnapshot(otherItem)
        var saveCalls = 0
        var shouldFail = true
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            if shouldFail {
                return .failure(StoreError.unavailable)
            }

            return Result { try context.save() }
        }

        guard case .failure(.persistence(let error)) = actions.delete(item, confirmed: true) else {
            Issue.record("個体削除の元の保存エラーが返されなかった")
            return
        }

        #expect(error as? StoreError == .unavailable)
        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        #expect(item.modelContext === context)
        #expect(item.product === product)
        #expect(ItemSnapshot(item) == original)
        let restored = try #require(context.fetch(FetchDescriptor<Item>()).first { $0.id == original.id })
        #expect(restored === item)
        try expectInventory(
            in: context, productID: productID, items: [original, siblingSnapshot],
            otherProductID: otherID, otherItems: [otherSnapshot]
        )
        try expectInventory(
            in: ModelContext(container), productID: productID, items: [original, siblingSnapshot],
            otherProductID: otherID, otherItems: [otherSnapshot]
        )

        // rollback後も同じ個体を渡し、入力や参照を作り直さずに再試行する。
        shouldFail = false
        try actions.delete(item, confirmed: true).get()

        #expect(saveCalls == 2)
        #expect(!context.hasChanges)
        try expectInventory(
            in: context, productID: productID, items: [siblingSnapshot],
            otherProductID: otherID, otherItems: [otherSnapshot]
        )
        try expectInventory(
            in: ModelContext(container), productID: productID, items: [siblingSnapshot],
            otherProductID: otherID, otherItems: [otherSnapshot]
        )
    }

    @Test func deletionRejectsUnmanagedAndForeignItemsWithoutSaving() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let owner = ModelContext(container)
        let product = try makeSavedProduct(in: owner)
        let saved = try makeSavedItem(in: owner, product: product)
        let unmanaged = makeExistingItem(product: Product(name: "未登録", type: "調味料"))
        let savedSnapshot = ItemSnapshot(saved)
        let unmanagedSnapshot = ItemSnapshot(unmanaged)
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        for item in [unmanaged, saved] {
            guard case .failure(.itemNotInContext) = actions.delete(item, confirmed: true) else {
                Issue.record("未管理または別contextの個体の削除が拒否されなかった")
                return
            }
        }

        #expect(saveCalls == 0)
        #expect(ItemSnapshot(unmanaged) == unmanagedSnapshot)
        #expect(ItemSnapshot(saved) == savedSnapshot)
        #expect(unmanaged.modelContext == nil)
        #expect(saved.modelContext === owner)
        #expect(saved.product === product)
        #expect(product.items?.map(\.id) == [savedSnapshot.id])
        expectProductValues(product)
        #expect(!context.hasChanges)
        #expect(!owner.hasChanges)
        let reader = ModelContext(container)
        let items = try reader.fetch(FetchDescriptor<Item>())
        #expect(items.count == 1)
        #expect(ItemSnapshot(try #require(items.first)) == savedSnapshot)
        expectProductValues(try #require(reader.fetch(FetchDescriptor<Product>()).first))
    }

    @Test(arguments: PendingEdit.allCases)
    private func deletionPreservesPendingInputWithoutSavingOrRollingBack(_ pendingEdit: PendingEdit) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let saved = try makeSavedItem(in: context, product: product)
        let savedSnapshot = ItemSnapshot(saved)
        let target: Item
        switch pendingEdit {
        case .item:
            target = saved
            target.expirationDate = expirationDate
        case .unrelatedProduct:
            target = saved
            other.name = "編集中のみそ"
        case .insertedItem:
            target = makeExistingItem(product: product)
            context.insert(target)
        }
        let pendingSnapshot = ItemSnapshot(target)
        let pendingName = other.name
        let pendingIDs = Set((product.items ?? []).map(\.id))
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.pendingChanges) = actions.delete(target, confirmed: true) else {
            Issue.record("未保存変更があるcontextで個体が削除された")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        #expect(ItemSnapshot(target) == pendingSnapshot)
        #expect(target.modelContext === context)
        #expect(target.product === product)
        #expect(Set((product.items ?? []).map(\.id)) == pendingIDs)
        expectProductValues(product)
        expectProductValues(other, name: pendingName)
        try expectInventory(
            in: ModelContext(container), productID: product.id, items: [savedSnapshot],
            otherProductID: other.id, otherItems: []
        )
    }

    private enum PendingItemChange: CaseIterable {
        case insert
        case delete
    }

    @Test(arguments: PendingItemChange.allCases)
    private func deletionPreservesUnrelatedPendingInsertionsAndDeletions(_ change: PendingItemChange) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let product = try makeSavedProduct(in: context)
        let other = try makeSavedProduct(in: context, name: "みそ")
        let item = try makeSavedItem(in: context, product: product)
        let original = ItemSnapshot(item)
        let unrelated = try makeSavedItem(in: context, product: other, status: .consumed)
        let unrelatedSnapshot = ItemSnapshot(unrelated)
        switch change {
        case .insert:
            context.insert(makeExistingItem(product: other))
        case .delete:
            context.delete(unrelated)
        }
        let pendingOtherIDs = Set((other.items ?? []).map(\.id))
        let pendingInsertions = Set(context.insertedModelsArray.map(\.persistentModelID))
        let pendingDeletions = Set(context.deletedModelsArray.map(\.persistentModelID))
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            return Result { try context.save() }
        }

        guard case .failure(.pendingChanges) = actions.delete(item, confirmed: true) else {
            Issue.record("無関係な個体の未保存追加・削除があるcontextで削除された")
            return
        }

        #expect(saveCalls == 0)
        #expect(context.hasChanges)
        #expect(ItemSnapshot(item) == original)
        #expect(item.product === product)
        #expect(product.items?.map(\.id) == [original.id])
        #expect(Set((other.items ?? []).map(\.id)) == pendingOtherIDs)
        #expect(Set(context.insertedModelsArray.map(\.persistentModelID)) == pendingInsertions)
        #expect(Set(context.deletedModelsArray.map(\.persistentModelID)) == pendingDeletions)
        expectProductValues(product)
        expectProductValues(other, name: "みそ")
        try expectInventory(
            in: ModelContext(container), productID: product.id, items: [original],
            otherProductID: other.id, otherItems: [unrelatedSnapshot]
        )
    }

    @Test func deletingTheLastItemKeepsTheProductAndItsValues() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let productID = product.id
        let item = try makeSavedItem(in: context, product: product, status: .consumed)

        try ItemActions(context: context).delete(item, confirmed: true).get()

        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Item>()) == 0)
        #expect((product.items ?? []).isEmpty)
        #expect(product.modelContext === context)
        expectProductValues(product)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let saved = try #require(products.first)
        #expect(saved.id == productID)
        #expect((saved.items ?? []).isEmpty)
        expectProductValues(saved)
    }

    @Test(arguments: ["", "futureStatus"])
    func deletionAcceptsUnknownSavedStatusesWithoutCoercingThem(_ rawValue: String) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let product = try makeSavedProduct(in: context)
        let item = try makeSavedItem(in: context, product: product)
        item.statusRawValue = rawValue
        try context.save()
        let original = ItemSnapshot(item)
        let productID = product.id
        var saveCalls = 0
        let actions = ItemActions(context: context) { context in
            saveCalls += 1
            // 保存を実行する前にも、未知の状態が既知の値へ書き換えられていない。
            #expect(item.statusRawValue == rawValue)
            #expect(item.status == nil)
            return Result { try context.save() }
        }

        guard case .failure(.deletionNotConfirmed) = actions.delete(item, confirmed: false) else {
            Issue.record("未知の状態の個体で削除確認の失敗結果が返されなかった")
            return
        }
        #expect(saveCalls == 0)
        #expect(ItemSnapshot(item) == original)
        #expect(!context.hasChanges)

        try actions.delete(item, confirmed: true).get()

        #expect(saveCalls == 1)
        #expect(!context.hasChanges)
        let reader = ModelContext(container)
        #expect(try reader.fetchCount(FetchDescriptor<Item>()) == 0)
        let products = try reader.fetch(FetchDescriptor<Product>())
        #expect(products.count == 1)
        let savedProduct = try #require(products.first)
        #expect(savedProduct.id == productID)
        #expect((savedProduct.items ?? []).isEmpty)
        expectProductValues(savedProduct)
    }

    @Test(arguments: ItemStatus.allCases)
    func deletionAndSurvivingRelationshipsPersistAfterReopeningTheStore(_ status: ItemStatus) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("deleted-items.store")
        let productID: UUID
        let otherID: UUID
        let siblingSnapshot: ItemSnapshot
        let otherSnapshot: ItemSnapshot

        do {
            let container = try makeContainer(at: url)
            let context = ModelContext(container)
            let product = try makeSavedProduct(in: context)
            let other = try makeSavedProduct(in: context, name: "みそ")
            let item = try makeSavedItem(in: context, product: product, status: status)
            productID = product.id
            otherID = other.id
            siblingSnapshot = ItemSnapshot(try makeSavedItem(in: context, product: product, status: .consumed))
            otherSnapshot = ItemSnapshot(try makeSavedItem(in: context, product: other))

            try ItemActions(context: context).delete(item, confirmed: true).get()

            #expect(!context.hasChanges)
        }

        let reopened = try makeContainer(at: url)
        try expectInventory(
            in: ModelContext(reopened), productID: productID, items: [siblingSnapshot],
            otherProductID: otherID, otherItems: [otherSnapshot]
        )
    }

    private func expectInventory(
        in context: ModelContext, productID: UUID, items expectedItems: [ItemSnapshot],
        otherProductID: UUID, otherItems expectedOtherItems: [ItemSnapshot]
    ) throws {
        let products = try context.fetch(FetchDescriptor<Product>())
        #expect(products.count == 2)
        #expect(Set(products.map(\.id)) == Set([productID, otherProductID]))
        let product = try #require(products.first { $0.id == productID })
        let other = try #require(products.first { $0.id == otherProductID })
        expectProductValues(product)
        expectProductValues(other, name: "みそ")
        #expect(Set((product.items ?? []).map(\.id)) == Set(expectedItems.map(\.id)))
        #expect(Set((other.items ?? []).map(\.id)) == Set(expectedOtherItems.map(\.id)))
        let items = try context.fetch(FetchDescriptor<Item>())
        let expected = expectedItems + expectedOtherItems
        #expect(items.count == expected.count)
        #expect(Set(items.map(\.id)) == Set(expected.map(\.id)))
        for snapshot in expected {
            let item = try #require(items.first { $0.id == snapshot.id })
            let owner = try #require(products.first { $0.id == snapshot.productID })
            #expect(ItemSnapshot(item) == snapshot)
            #expect(item.product === owner)
        }
    }

    private func expectTransitionedValues(
        _ item: Item, original: ItemSnapshot, transition: StatusTransition, confirmedDate: Date
    ) {
        #expect(item.id == original.id)
        #expect(item.product?.id == original.productID)
        #expect(item.expirationDate == original.expirationDate)
        #expect(item.status == transition.destination)
        #expect(item.statusRawValue == transition.destination.rawValue)
        #expect(item.updatedAt == registrationDate)
        switch transition {
        case .open:
            #expect(item.openingDate == confirmedDate)
            #expect(item.consumedDate == original.consumedDate)
        case .consume:
            #expect(item.openingDate == original.openingDate)
            #expect(item.consumedDate == confirmedDate)
        }
    }

    private struct ItemSnapshot: Equatable {
        let id: UUID
        let productID: UUID?
        let expirationDate: Date?
        let statusRawValue: String
        let openingDate: Date?
        let consumedDate: Date?
        let updatedAt: Date

        init(_ item: Item) {
            id = item.id
            productID = item.product?.id
            expirationDate = item.expirationDate
            statusRawValue = item.statusRawValue
            openingDate = item.openingDate
            consumedDate = item.consumedDate
            updatedAt = item.updatedAt
        }
    }

    private func calendar(secondsFromGMT: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: secondsFromGMT))
        return calendar
    }

    private func makeSavedItem(
        in context: ModelContext, product: Product, status: ItemStatus = .inUse
    ) throws -> Item {
        let item = Item(product: product, expirationDate: originalDate, status: status, updatedAt: originalDate)
        switch status {
        case .unopened:
            break
        case .inUse:
            item.openingDate = originalDate
        case .consumed:
            item.openingDate = originalDate
            item.consumedDate = originalDate.addingTimeInterval(172_800)
        }
        context.insert(item)
        try context.save()
        return item
    }

    private func expectEditedDates(_ item: Item, expiration: Date?, opening: Date?) {
        #expect(item.expirationDate == expiration)
        #expect(item.openingDate == opening)
        #expect(item.updatedAt == registrationDate)
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        if let url {
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSavedProduct(in context: ModelContext, name: String = "しょうゆ") throws -> Product {
        let product = Product(name: name, type: "調味料", updatedAt: originalDate)
        product.image = originalImage
        product.priceYen = 398
        product.calories = 1234
        product.protein = 1
        product.fat = 120
        product.sugar = 2
        product.carbohydrates = 456
        product.nutrientBasisAmount = 1500
        product.nutrientBasisUnit = "mL"
        context.insert(product)
        try context.save()
        return product
    }

    private func makeExistingItem(product: Product) -> Item {
        Item(
            product: product, expirationDate: originalDate, status: .inUse,
            openingDate: originalDate, updatedAt: originalDate
        )
    }

    private func expectProductValues(_ product: Product, name: String = "しょうゆ") {
        #expect(product.name == name)
        #expect(product.type == "調味料")
        #expect(product.image == originalImage)
        #expect(product.priceYen == 398)
        #expect(product.calories == 1234)
        #expect(product.protein == 1)
        #expect(product.fat == 120)
        #expect(product.sugar == 2)
        #expect(product.carbohydrates == 456)
        #expect(product.nutrientBasisAmount == 1500)
        #expect(product.nutrientBasisUnit == "mL")
        #expect(product.updatedAt == originalDate)
    }

    private func expectNewValues(_ item: Item, expiration: Date?) {
        #expect(item.expirationDate == expiration)
        #expect(item.status == .unopened)
        #expect(item.statusRawValue == "unopened")
        #expect(item.openingDate == nil)
        #expect(item.consumedDate == nil)
        #expect(item.updatedAt == registrationDate)
    }

    private func expectExistingValues(_ item: Item) {
        #expect(item.expirationDate == originalDate)
        #expect(item.status == .inUse)
        #expect(item.openingDate == originalDate)
        #expect(item.consumedDate == nil)
        #expect(item.updatedAt == originalDate)
    }
}
