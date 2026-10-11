import Foundation

/// 期限の表示状態。時計や保存モデルに依存せず、渡された暦のローカル日付で判定する。
nonisolated enum ExpirationState: Equatable, Sendable {
    case expired
    case expiringSoon
    case normal
    case unset

    enum CalculationError: Error, Equatable, Sendable {
        case dayCalculationFailed
    }

    /// 今日から7日後までを「期限が近い」とする。期限日の時刻は判定に含めない。
    init(expirationDate: Date?, now: Date, calendar: Calendar) throws {
        guard let expirationDate else {
            self = .unset
            return
        }

        let today = calendar.startOfDay(for: now)
        let expirationDay = calendar.startOfDay(for: expirationDate)

        guard expirationDay >= today else {
            self = .expired
            return
        }

        guard let lastSoonDay = calendar.date(byAdding: .day, value: 7, to: today) else {
            throw CalculationError.dayCalculationFailed
        }

        if expirationDay <= lastSoonDay {
            self = .expiringSoon
            return
        }

        self = .normal
    }
}
