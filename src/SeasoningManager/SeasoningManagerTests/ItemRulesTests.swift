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
        let item = try makeItem(status: .unopened)
        let original = Snapshot(item)
        context.insert(item)
        try context.save()

        let opening = date(day: 2)
        let openingUpdate = date(day: 4, hour: 12)
        try item.open(on: opening, now: openingUpdate, calendar: calendar()).get()
        try context.save()

        let openedReader = ModelContext(container)
        let opened = try #require(try openedReader.fetch(FetchDescriptor<Item>()).first)
        #expect(opened.status == .inUse)
        #expect(opened.openingDate == opening)
        #expect(opened.consumedDate == nil)
        #expect(opened.updatedAt == openingUpdate)

        let consumed = date(day: 6)
        let consumedUpdate = date(day: 7, hour: 12)
        try item.consume(on: consumed, now: consumedUpdate, calendar: calendar()).get()
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

    @Test func repeatedOpeningAndConsumptionLeaveDatesUnchanged() throws {
        let item = Item(product: try Product(name: "しょうゆ", type: "調味料"))
        try item.open(on: date(day: 2), now: date(day: 4), calendar: calendar()).get()
        let opened = Snapshot(item)
        guard case .failure(.invalidTransition) = item.open(on: date(day: 3), now: date(day: 5), calendar: calendar())
        else {
            Issue.record("使用中の個体の再開封を拒否しなかった")
            return
        }
        #expect(Snapshot(item) == opened)

        try item.consume(on: date(day: 6), now: date(day: 7), calendar: calendar()).get()
        let consumed = Snapshot(item)
        guard
            case .failure(.invalidTransition) = item.consume(on: date(day: 7), now: date(day: 8), calendar: calendar())
        else {
            Issue.record("使い切った個体の再操作を拒否しなかった")
            return
        }
        #expect(Snapshot(item) == consumed)
    }

    @Test func editingCanRepairMissingOpeningDateWithoutPartiallyApplyingAnInvalidEdit() throws {
        let item = Item(
            product: try Product(name: "しょうゆ", type: "調味料"), expirationDate: date(day: 1),
            status: .inUse, openingDate: nil, updatedAt: date(day: 2)
        )
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(item)
        try context.save()
        let original = Snapshot(item)
        let expiration = date(day: 20)
        guard
            case .failure(.futureOpeningDate) = item.updateDates(
                expirationDate: expiration, openingDate: date(day: 11), now: date(day: 10), calendar: calendar()
            )
        else {
            Issue.record("未来の開封日を拒否しなかった")
            return
        }
        #expect(Snapshot(item) == original)
        #expect(!context.hasChanges)
        try context.save()
        let reader = ModelContext(container)
        let saved = try #require(try reader.fetch(FetchDescriptor<Item>()).first)
        #expect(Snapshot(saved) == original)

        try item.updateDates(
            expirationDate: expiration, openingDate: date(day: 4), now: date(day: 10), calendar: calendar()
        ).get()
        #expect(item.status == .inUse)
        #expect(item.openingDate == date(day: 4))
        #expect(item.expirationDate == expiration)
        #expect(item.updatedAt == date(day: 10))
    }

    @Test(arguments: [ItemStatus.unopened, .inUse, .consumed])
    func allowsEditingDatesWithoutChangingStatus(_ status: ItemStatus) throws {
        let item = try makeItem(status: status)
        let consumed = item.consumedDate
        let opening = status == .unopened ? nil : date(day: 1)
        let now = date(day: 10, hour: 12)
        try item.updateDates(
            expirationDate: date(day: 12), openingDate: opening, now: now, calendar: calendar()
        ).get()

        #expect(item.expirationDate == date(day: 12))
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
    func invalidTargetDatesAndTransitionsReturnTheExpectedError(
        _ input: (source: ItemStatus, target: ItemStatus, openingDay: Int?, consumedDay: Int?, error: ValidationError)
    ) {
        let rules = ItemRules(
            status: input.target,
            openingDate: input.openingDay.map { date(day: $0) },
            consumedDate: input.consumedDay.map { date(day: $0) }
        )

        let result = rules.validate(from: input.source, now: date(day: 10, hour: 12), calendar: calendar())
        guard case .failure(let error) = result else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == input.error)
    }

    @Test(arguments: ["", "futureStatus"])
    func rejectsUnknownSavedStatusWithoutReplacingIt(_ rawValue: String) throws {
        let item = try makeItem(status: .unopened)
        item.setValue(forKey: \.statusRawValue, to: rawValue)
        let original = Snapshot(item)

        let updateResult = item.open(on: date(day: 2), now: date(day: 10), calendar: calendar())

        guard case .failure(let error) = updateResult else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == ValidationError.unknownCurrentStatus)

        #expect(Snapshot(item) == original)
        #expect(item.status == nil)
    }

    @Test func comparesCalendarDaysInsteadOfTimesWithinTheSameDay() throws {
        let item = try makeItem(status: .unopened)
        let opening = date(day: 10, hour: 23)
        let now = date(day: 10, hour: 1)
        try item.open(on: opening, now: now, calendar: calendar()).get()
        let consumed = date(day: 10)
        try item.consume(on: consumed, now: now, calendar: calendar()).get()

        #expect(item.openingDate == opening)
        #expect(item.consumedDate == consumed)
        #expect(item.status == .consumed)
    }

    @Test func openingDateUsesTheInjectedLocalDay() throws {
        let item = try makeItem(status: .unopened)
        let now = date(day: 10, hour: 16)
        let opening = date(day: 11, hour: 1)

        guard case .failure(let error) = item.open(on: opening, now: now, calendar: calendar()) else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == ValidationError.futureOpeningDate)

        try item.open(on: opening, now: now, calendar: calendar(offset: 9 * 3_600)).get()
        #expect(item.status == .inUse)
        #expect(item.openingDate == opening)
    }

    @Test func consumingOnAnEarlierLocalDayIsRejectedAcrossMidnight() throws {
        let item = try makeItem(status: .unopened)
        let now = date(day: 10)
        try item.open(on: date(day: 2, hour: 16), now: now, calendar: calendar()).get()
        let original = Snapshot(item)
        let consumed = date(day: 2, hour: 14)
        let updateResult = item.consume(on: consumed, now: now, calendar: calendar(offset: 9 * 3_600))

        guard case .failure(let error) = updateResult else {
            Issue.record("期待した失敗結果が返されなかった")
            return
        }
        #expect(error == ValidationError.consumedDateBeforeOpeningDate)
        #expect(Snapshot(item) == original)

        try item.consume(on: consumed, now: now, calendar: calendar()).get()
        #expect(item.status == .consumed)
    }

    @Test func futureConsumedDateIsAllowedByTheCurrentSpecification() throws {
        let item = try makeItem(status: .inUse)
        let future = date(day: 20)
        try item.consume(on: future, now: date(day: 10), calendar: calendar()).get()

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

    private func makeItem(status: ItemStatus) throws -> Item {
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
            product: try Product(name: "しょうゆ", type: "調味料"), expirationDate: date(day: 0),
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
