import XCTest
@testable import ACDCore

final class ReportParserTests: XCTestCase {
    private let parser = ReportParser()

    func testSubscriptionActiveColumnsSumMatchesProbeFixture() throws {
        let tsv = try fixture(named: "subscription_2026-02-18.tsv")
        let fallback = DateFormatter.ptDateFormatter.date(from: "2026-02-18")

        let rows = try parser.parseSubscription(tsv: tsv, fallbackDatePT: fallback)
        XCTAssertFalse(rows.isEmpty)

        let activeTotal = rows.reduce(0) {
            $0 + $1.activeStandard + $1.activeIntroTrial + $1.activeIntroPayUpFront + $1.activeIntroPayAsYouGo
        }
        let subscribersRaw = rows.reduce(0) { $0 + $1.subscribersRaw }

        XCTAssertEqual(activeTotal, 409, accuracy: 0.0001)
        XCTAssertEqual(subscribersRaw, 75, accuracy: 0.0001)
    }

    func testFinanceDetailHeaderWithMetadataPrefixParsesRows() throws {
        let tsv = try fixture(named: "finance_detail_z1_2026-02.tsv")

        let rows = try parser.parseFinance(
            tsv: tsv,
            fiscalMonth: "2026-02",
            regionCode: "Z1",
            vendorNumber: "TEST_VENDOR",
            reportVariant: "Z1"
        )

        XCTAssertFalse(rows.isEmpty)
        XCTAssertEqual(rows.first?.reportVariant, "Z1")
        XCTAssertEqual(rows.first?.countryOfSale, "AU")
    }

    private func fixture(named name: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try String(contentsOf: path, encoding: .utf8)
    }
}
