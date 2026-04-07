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
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscription_2026-02-18.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: try fixture(named: "subscription_2026-02-18.tsv")
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
        try recordReport(
            cacheStore: cacheStore,
            filename: "finance_detail_z1_2025-11.tsv",
            source: .finance,
            reportType: "FINANCE_DETAIL",
            reportSubType: "Z1",
            reportDateKey: "2025-11-FINANCE_DETAIL-Z1",
            text: try fixture(named: "finance_detail_z1_2026-02.tsv")
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
}
