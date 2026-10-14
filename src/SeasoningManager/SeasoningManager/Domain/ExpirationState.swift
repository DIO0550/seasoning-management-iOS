import Foundation

/// 期限の表示状態。時計や保存モデルに依存せず、渡された暦のローカル日付で判定する。
nonisolated enum ExpirationState: Equatable, Sendable {
    case expired
    case expiringSoon
    case normal
    case unset

    private static let expiringSoonThresholdDays = 7

    enum CalculationError: Error, Equatable, Sendable {
        case dayCalculationFailed
    }

    /// 今日から7日後までを「期限が近い」とする。期限日の時刻は判定に含めない。
    static func calculate(
        expirationDate: Date?, now: Date, calendar: Calendar
    ) -> Result<ExpirationState, CalculationError> {
        guard let expirationDate else {
            return .success(.unset)
        }

        let today = calendar.startOfDay(for: now)
        let expirationDay = calendar.startOfDay(for: expirationDate)

        guard expirationDay >= today else {
            return .success(.expired)
        }

        guard let lastSoonDay = calendar.date(byAdding: .day, value: Self.expiringSoonThresholdDays, to: today) else {
            return .failure(.dayCalculationFailed)
        }

        if expirationDay <= lastSoonDay {
            return .success(.expiringSoon)
        }

        return .success(.normal)
    }
}
