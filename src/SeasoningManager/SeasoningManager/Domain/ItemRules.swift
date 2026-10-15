import Foundation

/// 変更後の状態と日付。保存モデルを変更せずに、入力全体を検証する。
struct ItemRules {
    let status: ItemStatus
    var openingDate: Date? = nil
    var consumedDate: Date? = nil

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
        from currentStatus: ItemStatus?, now: Date, calendar: Calendar = .current
    ) -> Result<Void, ValidationError> {
        guard let currentStatus else {
            return .failure(.unknownCurrentStatus)
        }

        switch (currentStatus, status) {
        case (.unopened, .unopened), (.unopened, .inUse), (.inUse, .inUse), (.inUse, .consumed), (.consumed, .consumed):
            break
        default:
            return .failure(.invalidTransition)
        }

        switch status {
        case .unopened:
            guard openingDate == nil else {
                return .failure(.unexpectedOpeningDate)
            }

            guard consumedDate == nil else {
                return .failure(.unexpectedConsumedDate)
            }

            return .success(())
        case .inUse:
            guard consumedDate == nil else {
                return .failure(.unexpectedConsumedDate)
            }
        case .consumed:
            guard consumedDate != nil else {
                return .failure(.consumedDateRequired)
            }
        }

        guard let openingDate else {
            return .failure(.openingDateRequired)
        }

        let openingDay = calendar.startOfDay(for: openingDate)
        guard openingDay <= calendar.startOfDay(for: now) else {
            return .failure(.futureOpeningDate)
        }

        if let consumedDate {
            guard calendar.startOfDay(for: consumedDate) >= openingDay else {
                return .failure(.consumedDateBeforeOpeningDate)
            }
        }

        return .success(())
    }
}

extension Item {
    /// 全検証が成功した場合だけ反映する。ModelContextの保存・保存失敗時の復旧は呼び出し側が行う。
    func updateState(
        using rules: ItemRules, now: Date, calendar: Calendar = .current
    ) -> Result<Void, ItemRules.ValidationError> {
        rules.validate(from: status, now: now, calendar: calendar).map {
            statusRawValue = rules.status.rawValue
            openingDate = rules.openingDate
            consumedDate = rules.consumedDate
            updatedAt = now
        }
    }
}
