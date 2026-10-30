import Foundation
import XCTest
@testable import HesabCore

/// Replays phase1 tools/make_learning_oracle.js (real web learnCategory / learn*Subcategory / suggest*Candidates).
final class LearningTests: XCTestCase {
    func testLearningMatchesWeb() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "learning_oracle", withExtension: "json", subdirectory: "Goldens/import"))
        let o: JSONValue = try JSONCoding.decode(try Data(contentsOf: url))
        func ctx(_ s: String) -> LearnContext { s == "L" ? .ledger : (s == "I" ? .income : .personal) }
        var st: [String: JSONValue] = [:]
        for e in o["learn"]?.arrayValue ?? [] {
            let a = (e.arrayValue ?? []).compactMap(\.stringValue)
            Learning.learnCategory(&st, ctx(a[0]), desc: a[1], category: a[2])
            if !a[3].isEmpty { Learning.learnSubcategory(&st, ctx(a[0]), category: a[2], desc: a[1], sub: a[3]) }
        }
        // stored maps are the same as the web app's (key order aside)
        for (k, v) in o["maps"]?.objectValue ?? [:] {
            XCTAssertEqual(st[k] ?? .object([:]), v, k)
        }
        let queries = o["queries"]?.arrayValue ?? []
        let answers = o["answers"]?.arrayValue ?? []
        XCTAssertEqual(queries.count, answers.count)
        for (q, ans) in zip(queries, answers) {
            let a = (q.arrayValue ?? []).compactMap(\.stringValue)
            XCTAssertEqual(Learning.categoryCandidates(st, ctx(a[0]), desc: a[1]),
                           (ans["cats"]?.arrayValue ?? []).compactMap(\.stringValue), "cats: " + a[1])
            if !a[2].isEmpty {
                XCTAssertEqual(Learning.subcategoryCandidates(st, ctx(a[0]), category: a[2], desc: a[1]),
                               (ans["subs"]?.arrayValue ?? []).compactMap(\.stringValue), "subs: " + a[1])
            }
        }
    }

    func testStopwordsAndNumbers() {
        XCTAssertEqual(Learning.descWords("خرید ۱۲۳ میلگرد و سیمان"), ["میلگرد", "سیمان"])
        XCTAssertEqual(Learning.descSignature("سیمان میلگرد"), Learning.descSignature("میلگرد  سیمان"))
    }
}
