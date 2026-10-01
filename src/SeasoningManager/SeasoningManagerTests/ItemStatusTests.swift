import Foundation
import Testing
@testable import SeasoningManager

@MainActor
struct ItemStatusTests {
    @Test func storageValuesAndLabelsMatch() throws {
        let cases: [(ItemStatus, String, String)] = [
            (.unopened, "unopened", "未開封"),
            (.inUse, "inUse", "使用中"),
            (.consumed, "consumed", "使い切り"),
        ]
        #expect(ItemStatus.allCases.count == cases.count)
        for (status, rawValue, label) in cases {
            #expect(status.rawValue == rawValue)
            #expect(ItemStatus(rawValue: rawValue) == status)
            #expect(status.displayName == label)
            let data = try JSONEncoder().encode(status)
            #expect(try JSONDecoder().decode(String.self, from: data) == rawValue)
            #expect(try JSONDecoder().decode(ItemStatus.self, from: data) == status)
        }
    }

    @Test func unknownValuesAreRejected() {
        #expect(ItemStatus(rawValue: "unknown") == nil)
        #expect(ItemStatus(rawValue: "") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ItemStatus.self, from: Data("\"unknown\"".utf8))
        }
    }
}
