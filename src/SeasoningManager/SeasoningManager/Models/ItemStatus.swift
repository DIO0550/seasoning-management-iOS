/// rawValue は永続化用の固定値。表示名を変更しても保存値は変えない。
enum ItemStatus: String, Codable, CaseIterable {
    case unopened
    case inUse
    case consumed

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
