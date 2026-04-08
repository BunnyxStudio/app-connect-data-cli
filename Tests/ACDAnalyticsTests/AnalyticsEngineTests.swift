// Copyright 2026 BunnyxStudio
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import XCTest
import Foundation
@testable import ACDAnalytics
@testable import ACDCore

final class AnalyticsEngineTests: XCTestCase {
    func testSalesAggregateFromSubscriptionFixture() async throws {
        let cacheStore = try makeCacheStore()
        let fixtureText = try fixture(named: "subscription_2026-02-18.tsv")
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscription_2026-02-18.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: fixtureText
        )
        let subscriptionRows = try ReportParser().parseSubscription(
            tsv: fixtureText,
            fallbackDatePT: try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-02-18"))
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: Set(subscriptionRows.map {
                FXSeedRequest(dateKey: $0.businessDatePT.ptDateString, sourceCurrencyCode: $0.proceedsCurrency)
            })
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(sourceReport: ["subscription"])
            ),
            offline: true
        )

        let row = try XCTUnwrap(result.data.aggregates.first)
        XCTAssertEqual(result.dataset, .sales)
        XCTAssertEqual(try XCTUnwrap(row.metrics["subscribers"]), 75, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.metrics["activeSubscriptions"]), 409, accuracy: 0.0001)
    }

    func testReviewsCompareSupportsCustomWindow() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [
                    makeReview(id: "r1", date: "2026-02-18", rating: 5, responded: true),
                    makeReview(id: "r2", date: "2026-02-18", rating: 1, responded: false),
                    makeReview(id: "r3", date: "2026-02-17", rating: 4, responded: false)
                ]
            )
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .compare,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                compare: .custom,
                compareTime: QueryTimeSelection(datePT: "2026-02-17")
            ),
            offline: true
        )

        let row = try XCTUnwrap(result.data.comparisons.first)
        XCTAssertEqual(try XCTUnwrap(row.metrics["count"]?.current), 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.metrics["count"]?.previous), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.metrics["averageRating"]?.current), 3, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.metrics["averageRating"]?.previous), 4, accuracy: 0.0001)
    }

    func testFinanceAggregateFromFixture() async throws {
        let cacheStore = try makeCacheStore()
        let fixtureText = try fixture(named: "finance_detail_z1_2026-02.tsv")
        try recordReport(
            cacheStore: cacheStore,
            filename: "finance_detail_z1_2025-11.tsv",
            source: .finance,
            reportType: "FINANCE_DETAIL",
            reportSubType: "Z1",
            reportDateKey: "2025-11-FINANCE_DETAIL-Z1",
            text: fixtureText
        )
        let financeRows = try ReportParser().parseFinance(
            tsv: fixtureText,
            fiscalMonth: "2025-11",
            regionCode: "Z1",
            vendorNumber: "TEST_VENDOR",
            reportVariant: "FINANCE_DETAIL"
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: Set(financeRows.map {
                FXSeedRequest(dateKey: $0.businessDatePT.ptDateString, sourceCurrencyCode: $0.currency)
            })
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .finance,
                operation: .aggregate,
                time: QueryTimeSelection(fiscalMonth: "2025-11"),
                filters: QueryFilterSet(sourceReport: ["finance-detail"]),
                groupBy: [.territory]
            ),
            offline: true
        )

        XCTAssertEqual(result.dataset, .finance)
        XCTAssertFalse(result.data.aggregates.isEmpty)
        XCTAssertTrue(result.data.aggregates.contains { $0.group["territory"] == "CN" })
    }

    func testSalesAggregateRejectsUnknownSourceReport() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(sourceReport: ["not-a-report"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported sales source-report: not-a-report. Supported values: summary-sales, subscription, subscription-event, subscriber, pre-order, subscription-offer-redemption."
            )
        }
    }

    func testReviewsRecordsRejectUnknownSourceReport() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .reviews,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(sourceReport: ["not-a-report"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported reviews source-report: not-a-report. Supported values: customer-reviews."
            )
        }
    }

    func testFinanceAggregateRejectsUnknownSourceReport() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .finance,
                    operation: .aggregate,
                    time: QueryTimeSelection(fiscalMonth: "2025-11"),
                    filters: QueryFilterSet(sourceReport: ["not-a-report"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported finance source-report: not-a-report. Supported values: financial, finance-detail."
            )
        }
    }

    func testFinanceReportTypesDefaultsToBothWhenSourceReportIsOmitted() throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())

        XCTAssertEqual(
            engine.financeReportTypes(for: []),
            [.financial, .financeDetail]
        )
    }

    func testFinanceReportTypesOnlyIncludesRequestedSourceReport() throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())

        XCTAssertEqual(
            engine.financeReportTypes(for: ["financial"]),
            [.financial]
        )
        XCTAssertEqual(
            engine.financeReportTypes(for: ["finance-detail"]),
            [.financeDetail]
        )
    }

    func testAnalyticsAggregateRejectsUnknownSourceReport() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .analytics,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(sourceReport: ["not-a-report"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported analytics source-report: not-a-report. Supported values: acquisition, engagement, usage, performance."
            )
        }
    }

    func testSalesAggregateNormalizesMixedCurrenciesToUSD() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_mixed_2026-02-18.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: """
            Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
            2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t10\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t10\tUSD
            2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t1000\tJPY\tJP\tiPhone\t123\t1.0\t\t\tios\t1000\tJPY
            """
        )
        try writeFXRates(
            cacheStore: cacheStore,
            json: """
            {
              "2026-02-18|JPY": {
                "requestDateKey": "2026-02-18",
                "sourceDateKey": "2026-02-18",
                "currencyCode": "JPY",
                "usdPerUnit": 0.01,
                "fetchedAt": "2026-02-19T00:00:00Z"
              }
            }
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        let row = try XCTUnwrap(result.data.aggregates.first)
        XCTAssertEqual(try XCTUnwrap(row.metrics["proceeds"]), 20, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.metrics["sales"]), 20, accuracy: 0.0001)
        XCTAssertNil(row.metrics["proceedsRaw"])
        XCTAssertNil(row.metrics["salesRaw"])
        XCTAssertTrue(result.warnings.contains { $0.message.contains("USD") })
    }

    func testSalesAggregateNormalizesMixedCurrenciesToConfiguredCurrency() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_mixed_2026-02-18.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: """
            Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
            2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t10\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t10\tUSD
            2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t1000\tJPY\tJP\tiPhone\t123\t1.0\t\t\tios\t1000\tJPY
            """
        )
        try writeFXRates(
            cacheStore: cacheStore,
            json: """
            {
              "2026-02-18|USD|CNY": {
                "requestDateKey": "2026-02-18",
                "sourceDateKey": "2026-02-18",
                "sourceCurrencyCode": "USD",
                "targetCurrencyCode": "CNY",
                "ratePerUnit": 7.2,
                "fetchedAt": "2026-02-19T00:00:00Z"
              },
              "2026-02-18|JPY|CNY": {
                "requestDateKey": "2026-02-18",
                "sourceDateKey": "2026-02-18",
                "sourceCurrencyCode": "JPY",
                "targetCurrencyCode": "CNY",
                "ratePerUnit": 0.072,
                "fetchedAt": "2026-02-19T00:00:00Z"
              }
            }
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, reportingCurrency: "CNY")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        let row = try XCTUnwrap(result.data.aggregates.first)
        XCTAssertEqual(try XCTUnwrap(row.metrics["proceeds"]), 144, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(row.metrics["sales"]), 144, accuracy: 0.0001)
        XCTAssertTrue(result.warnings.contains { $0.message.contains("CNY") })
    }

    private func makeCacheStore() throws -> CacheStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()
        return cacheStore
    }

    private func recordReport(
        cacheStore: CacheStore,
        filename: String,
        source: ReportSource,
        reportType: String,
        reportSubType: String,
        reportDateKey: String,
        text: String
    ) throws {
        let fileURL = cacheStore.reportsDirectory.appendingPathComponent(filename)
        try LocalFileSecurity.writePrivateData(Data(text.utf8), to: fileURL)
        _ = try cacheStore.record(
            report: DownloadedReport(
                source: source,
                reportType: reportType,
                reportSubType: reportSubType,
                queryHash: filename,
                reportDateKey: reportDateKey,
                vendorNumber: "TEST_VENDOR",
                fileURL: fileURL,
                rawText: text
            )
        )
    }

    private func writeFXRates(cacheStore: CacheStore, json: String) throws {
        try LocalFileSecurity.writePrivateData(Data(json.utf8), to: cacheStore.fxRatesURL)
    }

    private func writeFXRates(
        cacheStore: CacheStore,
        requests: Set<FXSeedRequest>,
        targetCurrencyCode: String = "USD",
        ratePerUnit: Double = 1
    ) throws {
        struct SeededFXRate: Codable {
            var requestDateKey: String
            var sourceDateKey: String
            var sourceCurrencyCode: String
            var targetCurrencyCode: String
            var ratePerUnit: Double
            var fetchedAt: Date
        }

        let normalizedTargetCurrency = targetCurrencyCode.normalizedCurrencyCode
        let payload = Dictionary(uniqueKeysWithValues: requests.map { request in
            let normalizedSourceCurrency = request.sourceCurrencyCode.normalizedCurrencyCode
            let key = "\(request.dateKey)|\(normalizedSourceCurrency)|\(normalizedTargetCurrency)"
            return (
                key,
                SeededFXRate(
                    requestDateKey: request.dateKey,
                    sourceDateKey: request.dateKey,
                    sourceCurrencyCode: normalizedSourceCurrency,
                    targetCurrencyCode: normalizedTargetCurrency,
                    ratePerUnit: normalizedSourceCurrency == normalizedTargetCurrency ? 1 : ratePerUnit,
                    fetchedAt: Date(timeIntervalSince1970: 0)
                )
            )
        })

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try LocalFileSecurity.writePrivateData(try encoder.encode(payload), to: cacheStore.fxRatesURL)
    }

    private struct FXSeedRequest: Hashable {
        var dateKey: String
        var sourceCurrencyCode: String
    }

    private func makeReview(id: String, date: String, rating: Int, responded: Bool) throws -> ASCLatestReview {
        ASCLatestReview(
            id: id,
            appID: "6502647802",
            appName: "Hive",
            bundleID: "studio.bunny.hive",
            rating: rating,
            title: "Review \(id)",
            body: "Body \(id)",
            reviewerNickname: "tester",
            territory: "US",
            createdDate: try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: date)),
            developerResponse: responded ? ASCLatestReviewDeveloperResponse(
                id: "response-\(id)",
                body: "Thanks",
                lastModifiedDate: try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: date)),
                state: "PUBLISHED"
            ) : nil
        )
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

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ errorHandler: (Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown")
        } catch {
            errorHandler(error)
        }
    }
}
