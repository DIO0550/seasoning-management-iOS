/// 調味料の個体の状態。保存値は表示名と分け、未知の値を既知の状態へ補完しない。
enum ItemStatus: String, CaseIterable, Codable, Sendable {
    case unopened = "unopened"
    case inUse = "inUse"
    case consumed = "consumed"

    var displayName: String {
        switch self {
        case .unopened:
            return "未開封"
        case .inUse:
            return "使用中"
        case .consumed:
            return "使い切り"
        }
    }
}
