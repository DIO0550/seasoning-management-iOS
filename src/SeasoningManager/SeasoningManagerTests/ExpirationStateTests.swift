import Foundation
import Testing
@testable import SeasoningManager

@MainActor
struct ExpirationStateTests {
    @Test(
        arguments: [
            (9, ExpirationState.expired),
            (10, .expiringSoon),
            (11, .expiringSoon),
            (16, .expiringSoon),
            (17, .expiringSoon),
            (18, .normal),
        ],
        [(0, 23), (23, 0)]
    )
    func classifiesLocalDaysRegardlessOfTime(
        _ input: (expirationDay: Int, expected: ExpirationState),
        _ hours: (now: Int, expiration: Int)
    ) throws {
        let calendar = try makeCalendar()
        let now = try date(day: 10, hour: hours.now, calendar: calendar)
        let expiration = try date(day: input.expirationDay, hour: hours.expiration, calendar: calendar)

        let state = ExpirationState.calculate(expirationDate: expiration, now: now, calendar: calendar)

        #expect(state == .success(input.expected))
    }

    @Test func missingExpirationIsUnset() throws {
        let calendar = try makeCalendar()
        let now = try date(day: 10, calendar: calendar)

        #expect(ExpirationState.calculate(expirationDate: nil, now: now, calendar: calendar) == .success(.unset))
    }

    @Test(
        arguments: [
            (10, ExpirationState.expiringSoon, ExpirationState.expired),
            (18, .normal, .expiringSoon),
        ]
    )
    func updatesAtLocalMidnight(_ input: (expirationDay: Int, before: ExpirationState, after: ExpirationState)) throws {
        let calendar = try makeCalendar()
        let expiration = try date(day: input.expirationDay, hour: 12, calendar: calendar)
        let beforeMidnight = try date(day: 10, hour: 23, minute: 59, second: 59, calendar: calendar)
        let afterMidnight = try date(day: 11, calendar: calendar)

        let before = ExpirationState.calculate(expirationDate: expiration, now: beforeMidnight, calendar: calendar)
        let after = ExpirationState.calculate(expirationDate: expiration, now: afterMidnight, calendar: calendar)

        #expect(before == .success(input.before))
        #expect(after == .success(input.after))
    }

    @Test(
        arguments: [
            (10, 14, ExpirationState.expiringSoon, ExpirationState.expired),
            (18, 0, .normal, .expiringSoon),
        ]
    )
    func usesTheInjectedTimeZone(
        _ input: (expirationDay: Int, expirationHour: Int, utc: ExpirationState, tokyo: ExpirationState)
    ) throws {
        let utc = try makeCalendar(timeZone: "UTC")
        let tokyo = try makeCalendar()
        let now = try date(day: 10, hour: 16, calendar: utc)
        let expiration = try date(day: input.expirationDay, hour: input.expirationHour, calendar: utc)

        let utcState = ExpirationState.calculate(expirationDate: expiration, now: now, calendar: utc)
        let tokyoState = ExpirationState.calculate(expirationDate: expiration, now: now, calendar: tokyo)

        #expect(utcState == .success(input.utc))
        #expect(tokyoState == .success(input.tokyo))
    }

    @Test(
        arguments: [
            (2026, 1, 28, 2026, 2, 4, ExpirationState.expiringSoon),
            (2026, 1, 28, 2026, 2, 5, .normal),
            (2026, 12, 25, 2027, 1, 1, .expiringSoon),
            (2026, 12, 25, 2027, 1, 2, .normal),
            (2024, 2, 23, 2024, 3, 1, .expiringSoon),
            (2024, 2, 23, 2024, 3, 2, .normal),
        ]
    )
    func handlesMonthYearAndLeapDayBoundaries(
        _ input: (
            year: Int, month: Int, day: Int,
            expirationYear: Int, expirationMonth: Int, expirationDay: Int, expected: ExpirationState
        )
    ) throws {
        let calendar = try makeCalendar()
        let now = try date(year: input.year, month: input.month, day: input.day, calendar: calendar)
        let expiration = try date(
            year: input.expirationYear, month: input.expirationMonth, day: input.expirationDay,
            hour: 23, minute: 59, second: 59, calendar: calendar
        )

        let state = ExpirationState.calculate(expirationDate: expiration, now: now, calendar: calendar)

        #expect(state == .success(input.expected))
    }

    @Test(
        arguments: [
            (3, 7, 3, 14, ExpirationState.expiringSoon),
            (3, 7, 3, 15, .normal),
            (10, 31, 11, 7, .expiringSoon),
            (10, 31, 11, 8, .normal),
        ],
        [0, 23]
    )
    func countsCalendarDaysAcrossDaylightSavingChanges(
        _ input: (month: Int, day: Int, expirationMonth: Int, expirationDay: Int, expected: ExpirationState),
        _ expirationHour: Int
    ) throws {
        let calendar = try makeCalendar(timeZone: "America/Los_Angeles")
        let now = try date(month: input.month, day: input.day, calendar: calendar)
        let expiration = try date(
            month: input.expirationMonth, day: input.expirationDay, hour: expirationHour, calendar: calendar
        )

        let state = ExpirationState.calculate(expirationDate: expiration, now: now, calendar: calendar)

        #expect(state == .success(input.expected))
    }

    private func makeCalendar(timeZone identifier: String = "Asia/Tokyo") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    private func date(
        year: Int = 2026, month: Int = 10, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            )
        )
    }
}
