import Foundation
import SwiftData
import Testing
@testable import SeasoningManager

@MainActor
struct ItemRulesTests {
    typealias ValidationError = ItemRules.ValidationError

    @Test func openingAndConsumingPersistAllFieldsTogether() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let item = makeItem(status: .unopened)
        let original = Snapshot(item)
        context.insert(item)
        try context.save()

        let opening = date(day: 2)
        let openingUpdate = date(day: 4, hour: 12)
        try item.updateState(
            using: ItemRules(status: .inUse, openingDate: opening),
            now: openingUpdate, calendar: calendar()
        ).get()
        try context.save()

        let openedReader = ModelContext(container)
        let opened = try #require(try openedReader.fetch(FetchDescriptor<Item>()).first)
        #expect(opened.status == .inUse)
        #expect(opened.openingDate == opening)
        #expect(opened.consumedDate == nil)
        #expect(opened.updatedAt == openingUpdate)

        let consumed = date(day: 6)
        let consumedUpdate = date(day: 7, hour: 12)
        try item.updateState(
            using: ItemRules(status: .consumed, openingDate: opening, consumedDate: consumed),
            now: consumedUpdate, calendar: calendar()
        ).get()
        try context.save()

        let consumedReader = ModelContext(container)
        let saved = try #require(try consumedReader.fetch(FetchDescriptor<Item>()).first)
        #expect(saved.status == .consumed)
        #expect(saved.openingDate == opening)
        #expect(saved.consumedDate == consumed)
        #expect(saved.updatedAt == consumedUpdate)
        #expect(saved.id == original.id)
        #expect(saved.product?.id == original.productID)
        #expect(saved.expirationDate == original.expirationDate)
    }

    @Test(arguments: [ItemStatus.unopened, .inUse, .consumed])
    func allowsEditingDatesWithoutChangingStatus(_ status: ItemStatus) throws {
        let item = makeItem(status: status)
        var opening: Date?
        var consumed: Date?

        switch status {
        case .unopened:
            break
        case .inUse:
            opening = date(day: 4)
        case .consumed:
            opening = date(day: 4)
            consumed = date(day: 5)
        }

        let rules = ItemRules(status: status, openingDate: opening, consumedDate: consumed)
        let now = date(day: 10, hour: 12)
        try item.updateState(using: rules, now: now, calendar: calendar()).get()

        #expect(item.status == status)
        #expect(item.openingDate == opening)
        #expect(item.consumedDate == consumed)
        #expect(item.updatedAt == now)
    }

    @Test(
        arguments: [
            (ItemStatus.unopened, ItemStatus.consumed, 2, 3, ValidationError.invalidTransition),
            (.inUse, .unopened, nil, nil, .invalidTransition),
            (.consumed, .unopened, nil, nil, .invalidTransition),
            (.consumed, .inUse, 2, nil, .invalidTransition),
            (.unopened, .unopened, 2, nil, .unexpectedOpeningDate),
            (.unopened, .unopened, nil, 3, .unexpectedConsumedDate),
            (.unopened, .inUse, nil, nil, .openingDateRequired),
            (.unopened, .inUse, 2, 3, .unexpectedConsumedDate),
            (.unopened, .inUse, 11, nil, .futureOpeningDate),
            (.inUse, .inUse, nil, nil, .openingDateRequired),
            (.inUse, .inUse, 11, nil, .futureOpeningDate),
            (.inUse, .consumed, nil, 3, .openingDateRequired),
            (.inUse, .consumed, 2, nil, .consumedDateRequired),
            (.inUse, .consumed, 2, 1, .consumedDateBeforeOpeningDate),
            (.consumed, .consumed, 4, 3, .consumedDateBeforeOpeningDate),
        ] as [(ItemStatus, ItemStatus, Int?, Int?, ValidationError)]
    )
    func rejectedChangesLeaveModelAndSavedFieldsUntouched(
        _ input: (source: ItemStatus, target: ItemStatus, openingDay: Int?, consumedDay: Int?, error: ValidationError)
    ) throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let item = makeItem(status: input.source)
        context.insert(item)
        try context.save()
        let original = Snapshot(item)
        let rules = ItemRules(
            status: input.target,
            openingDate: input.openingDay.map { date(day: $0) },
            consumedDate: input.consumedDay.map { date(day: $0) }
        )

        guard case .failure(let error) = item.updateState(
            using: rules, now: date(day: 10, hour: 12), calendar: calendar()
        ) else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == input.error)

        #expect(Snapshot(item) == original)
        #expect(!context.hasChanges)
        // 失敗後に保存を呼んでも、部分更新された値がストアに入らない。
        try context.save()
        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<Item>()).first)
        #expect(Snapshot(saved) == original)
    }

    @Test(arguments: ["", "futureStatus"])
    func rejectsUnknownSavedStatusWithoutReplacingIt(_ rawValue: String) {
        let item = makeItem(status: .unopened)
        item.statusRawValue = rawValue
        let original = Snapshot(item)

        guard case .failure(let error) = item.updateState(
            using: ItemRules(status: .inUse, openingDate: date(day: 2)),
            now: date(day: 10), calendar: calendar()
        ) else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == ValidationError.unknownCurrentStatus)

        #expect(Snapshot(item) == original)
        #expect(item.status == nil)
    }

    @Test func comparesCalendarDaysInsteadOfTimesWithinTheSameDay() throws {
        let item = makeItem(status: .unopened)
        let opening = date(day: 10, hour: 23)
        let now = date(day: 10, hour: 1)
        try item.updateState(
            using: ItemRules(status: .inUse, openingDate: opening),
            now: now, calendar: calendar()
        ).get()
        let consumed = date(day: 10)
        try item.updateState(
            using: ItemRules(status: .consumed, openingDate: opening, consumedDate: consumed),
            now: now, calendar: calendar()
        ).get()

        #expect(item.openingDate == opening)
        #expect(item.consumedDate == consumed)
        #expect(item.status == .consumed)
    }

    @Test func openingDateUsesTheInjectedLocalDay() throws {
        let item = makeItem(status: .unopened)
        let now = date(day: 10, hour: 16)
        let rules = ItemRules(status: .inUse, openingDate: date(day: 11, hour: 1))

        guard case .failure(let error) = item.updateState(using: rules, now: now, calendar: calendar()) else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == ValidationError.futureOpeningDate)

        try item.updateState(using: rules, now: now, calendar: calendar(offset: 9 * 3_600)).get()
        #expect(item.status == .inUse)
        #expect(item.openingDate == rules.openingDate)
    }

    @Test func consumingOnAnEarlierLocalDayIsRejectedAcrossMidnight() throws {
        let item = makeItem(status: .inUse)
        let original = Snapshot(item)
        let rules = ItemRules(
            status: .consumed,
            openingDate: date(day: 2, hour: 16),
            consumedDate: date(day: 2, hour: 14)
        )

        guard case .failure(let error) = item.updateState(
            using: rules, now: date(day: 10), calendar: calendar(offset: 9 * 3_600)
        ) else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == ValidationError.consumedDateBeforeOpeningDate)
        #expect(Snapshot(item) == original)

        try item.updateState(using: rules, now: date(day: 10), calendar: calendar()).get()
        #expect(item.status == .consumed)
    }

    @Test func futureConsumedDateIsAllowedByTheCurrentSpecification() throws {
        let item = makeItem(status: .inUse)
        let future = date(day: 20)
        try item.updateState(
            using: ItemRules(status: .consumed, openingDate: item.openingDate, consumedDate: future),
            now: date(day: 10), calendar: calendar()
        ).get()

        #expect(item.status == .consumed)
        #expect(item.consumedDate == future)
    }

    @Test(
        arguments: [
            (nil, ItemStatus.consumed, 11, 1, ValidationError.unknownCurrentStatus),
            (.unopened, .consumed, nil, nil, .invalidTransition),
            (.unopened, .unopened, 2, 3, .unexpectedOpeningDate),
            (.inUse, .consumed, nil, nil, .consumedDateRequired),
            (.inUse, .consumed, nil, 1, .openingDateRequired),
            (.inUse, .consumed, 11, 1, .futureOpeningDate),
        ] as [(ItemStatus?, ItemStatus, Int?, Int?, ValidationError)]
    )
    func validationReportsTheFirstErrorWhenMultipleRulesFail(
        _ input: (source: ItemStatus?, target: ItemStatus, openingDay: Int?, consumedDay: Int?, error: ValidationError)
    ) {
        let rules = ItemRules(
            status: input.target,
            openingDate: input.openingDay.map { date(day: $0) },
            consumedDate: input.consumedDay.map { date(day: $0) }
        )
        let result = rules.validate(from: input.source, now: date(day: 10), calendar: calendar())

        guard case .failure(let error) = result else {
            Issue.record("競合する不正入力に失敗結果が返されなかった")
            return
        }
        #expect(error == input.error)
    }

    private func date(day: Int, hour: Int = 0) -> Date {
        Date(timeIntervalSince1970: Double(day * 86_400 + hour * 3_600))
    }

    private func calendar(offset: Int = 0) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offset)!
        return calendar
    }

    private func makeItem(status: ItemStatus) -> Item {
        var opening: Date?
        var consumed: Date?

        switch status {
        case .unopened:
            break
        case .inUse:
            opening = date(day: 2)
        case .consumed:
            opening = date(day: 2)
            consumed = date(day: 3)
        }

        return Item(
            product: Product(name: "しょうゆ", type: "調味料"), expirationDate: date(day: 0),
            status: status, openingDate: opening, consumedDate: consumed, updatedAt: date(day: 1)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Product.self, Item.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private struct Snapshot: Equatable {
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
}
