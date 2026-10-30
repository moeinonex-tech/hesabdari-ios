import Foundation
import XCTest
@testable import HesabCore

/// Replays phase1 tools/make_quote_bulk_oracle.js (real web quoteBulkParseRaw).
final class QuoteBulkTests: XCTestCase {
    func testParserMatchesWeb() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "quote_bulk_oracle", withExtension: "json", subdirectory: "Goldens/import"))
        let o: JSONValue = try JSONCoding.decode(try Data(contentsOf: url))
        let cases = try XCTUnwrap(o["cases"]?.arrayValue)
        XCTAssertEqual(cases.count, 5)
        for c in cases {
            let input = c["input"]?.stringValue ?? ""
            let got = QuoteBulk.parse(input)
            let want = (c["records"]?.arrayValue ?? []).map {
                BulkQuote(text: $0["text"]?.stringValue ?? "", author: $0["author"]?.stringValue ?? "", suspicious: $0["suspicious"]?.boolValue ?? false)
            }
            XCTAssertEqual(got, want, input)
        }
    }

    func testAddSkipsShort() {
        let r = QuoteBulk.add([:], [BulkQuote(text: "abc", author: "", suspicious: false), BulkQuote(text: " چهار حرف ", author: " x ", suspicious: true)])
        XCTAssertEqual(r.added, 1)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertEqual(r.state["customQuotes"]?.arrayValue?.first?["author"]?.stringValue, "x")
    }

    func testClearLearning() {
        let st = QuoteBulk.clearLearning(["ledgerDescMap": .object(["a": .string("b")]), "expenses": .array([.null])])
        XCTAssertEqual(st["ledgerDescMap"], .object([:]))
        XCTAssertEqual(st["expenses"], .array([.null]))
        XCTAssertEqual(st["incomeSubKeywordMap"], .object([:]))
    }
}
