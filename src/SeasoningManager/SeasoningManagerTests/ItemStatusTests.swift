import Foundation
import Testing
@testable import SeasoningManager

@MainActor
struct ItemStatusTests {
    @Test func statesMatchSpecifiedStorageValuesAndDisplayNames() {
        let expected: [(status: ItemStatus, rawValue: String, displayName: String)] = [
            (.unopened, "unopened", "未開封"),
            (.inUse, "inUse", "使用中"),
            (.consumed, "consumed", "使い切り")
        ]

        #expect(ItemStatus.allCases == expected.map(\.status))

        for entry in expected {
            #expect(entry.status.rawValue == entry.rawValue)
            #expect(entry.status.displayName == entry.displayName)
            #expect(ItemStatus(rawValue: entry.rawValue) == entry.status)
        }
    }

    @Test(arguments: [ItemStatus.unopened, .inUse, .consumed])
    func statesEncodeAsStorageStringsAndRoundTrip(_ status: ItemStatus) throws {
        let data = try JSONEncoder().encode(status)

        #expect(String(decoding: data, as: UTF8.self) == "\"\(status.rawValue)\"")
        #expect(try JSONDecoder().decode(ItemStatus.self, from: data) == status)
    }

    @Test(arguments: ["", "unknown", "UNOPENED", "inuse", " inUse ", "未開封"])
    func unknownStorageValuesAreRejected(_ rawValue: String) {
        #expect(ItemStatus(rawValue: rawValue) == nil)
    }

    @Test(arguments: ["", "unknown", "UNOPENED", "inuse", " inUse ", "未開封"])
    func unknownEncodedValuesFailToDecode(_ rawValue: String) throws {
        let data = try JSONEncoder().encode(rawValue)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ItemStatus.self, from: data)
        }
    }
}
