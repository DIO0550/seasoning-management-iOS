import Foundation

/// 変更後の状態と日付。保存モデルを変更せずに、入力全体を検証する。
struct ItemRules {
    let status: ItemStatus
    let openingDate: Date?
    let consumedDate: Date?

    init(status: ItemStatus, openingDate: Date? = nil, consumedDate: Date? = nil) {
        self.status = status
        self.openingDate = openingDate
        self.consumedDate = consumedDate
    }

    nonisolated enum ValidationError: Error, Equatable, Sendable {
        case unknownCurrentStatus
        case invalidTransition
        case openingDateRequired
        case unexpectedOpeningDate
        case consumedDateRequired
        case unexpectedConsumedDate
        case futureOpeningDate
        case consumedDateBeforeOpeningDate
    }

    /// 同状態の編集と、未開封→使用中→使い切りの一段階の遷移だけを許可する。
    func validate(
        from currentStatus: ItemStatus?, requiring source: ItemStatus? = nil,
        now: Date, calendar: Calendar = .current
    ) -> Result<ItemLifecycle, ValidationError> {
        ItemLifecycle.validated(self, from: currentStatus, requiring: source, now: now, calendar: calendar)
    }
}

/// 検証済みの個体状態。各状態で必要な日付は必須で、未開封には日付がない。
struct ItemLifecycle {
    enum Stage {
        case unopened
        case inUse(openingDate: Date)
        case consumed(openingDate: Date, consumedDate: Date)
    }

    let stage: Stage

    private init(_ stage: Stage) {
        self.stage = stage
    }

    fileprivate static func validated(
        _ rules: ItemRules, from currentStatus: ItemStatus?, requiring source: ItemStatus?, now: Date,
        calendar: Calendar
    ) -> Result<Self, ItemRules.ValidationError> {
        guard let currentStatus else {
            return .failure(.unknownCurrentStatus)
        }

        // 開封・使い切りでは同状態への再操作を拒否する。日付編集は同状態を許す。
        if let source, currentStatus != source {
            return .failure(.invalidTransition)
        }

        switch (currentStatus, rules.status) {
        case (.unopened, .unopened), (.unopened, .inUse), (.inUse, .inUse), (.inUse, .consumed), (.consumed, .consumed):
            break
        default:
            return .failure(.invalidTransition)
        }

        switch rules.status {
        case .unopened:
            guard rules.openingDate == nil else {
                return .failure(.unexpectedOpeningDate)
            }

            guard rules.consumedDate == nil else {
                return .failure(.unexpectedConsumedDate)
            }

            return .success(ItemLifecycle(.unopened))
        case .inUse:
            guard rules.consumedDate == nil else {
                return .failure(.unexpectedConsumedDate)
            }
        case .consumed:
            guard rules.consumedDate != nil else {
                return .failure(.consumedDateRequired)
            }
        }

        guard let openingDate = rules.openingDate else {
            return .failure(.openingDateRequired)
        }

        let openingDay = calendar.startOfDay(for: openingDate)
        guard openingDay <= calendar.startOfDay(for: now) else {
            return .failure(.futureOpeningDate)
        }

        guard let consumedDate = rules.consumedDate else {
            return .success(ItemLifecycle(.inUse(openingDate: openingDate)))
        }

        guard calendar.startOfDay(for: consumedDate) >= openingDay else {
            return .failure(.consumedDateBeforeOpeningDate)
        }

        return .success(ItemLifecycle(.consumed(openingDate: openingDate, consumedDate: consumedDate)))
    }
}
