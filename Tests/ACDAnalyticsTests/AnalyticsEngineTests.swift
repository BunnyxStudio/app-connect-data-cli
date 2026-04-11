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
    override func tearDown() {
        AnalyticsStubURLProtocol.requestHandler = nil
        super.tearDown()
    }

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

    func testSalesRecordsKeepDailySummaryWhenMonthlyCacheIsMissing() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-2026-03-01.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-03-01",
            text: """
            Date\tTitle\tParent Identifier\tApple Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCustomer Price\tCustomer Currency\tTerritory\tDevice\tProduct Type Identifier
            2026-03-01\tTest App\t123456789\t123456789\t1\t1\tUSD\t1\tUSD\tUS\tiPhone\t1
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(startDatePT: "2026-03-01", endDatePT: "2026-03-31"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["date"], "2026-03-01")
    }

    func testSalesAggregateGroupsSummarySalesByParentAppInsteadOfProductTitle() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-summary-grouping.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tTitle\tParent Identifier\tApple Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCustomer Price\tCustomer Currency\tTerritory\tDevice\tProduct Type Identifier\tSKU
            2026-04-01\tMy App\t\t123456789\t1\t5\tUSD\t5\tUSD\tUS\tiPhone\t1\tapp.main
            2026-04-01\tCoin Pack A\t123456789\t111\t1\t1\tUSD\t1\tUSD\tUS\tiPhone\tIA1\tcoin.a
            2026-04-01\tCoin Pack B\t123456789\t222\t1\t2\tUSD\t2\tUSD\tUS\tiPhone\tIA1\tcoin.b
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, reportingCurrency: "USD")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"]),
                groupBy: [.app]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 1)
        XCTAssertEqual(result.data.aggregates.first?.group["app"], "123456789")
        XCTAssertEqual(result.data.aggregates.first?.metrics["proceeds"], 8)
    }

    func testSubscriptionEventRecordsMatchAppAppleIDFilter() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscription-event.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION_EVENT",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tStandard Subscription Duration\tEvent\tEvent Count\tDeveloper Proceeds\tProceeds Currency\tDevice\tCountry
            2026-04-01\tTest App\t123456789\tPro Monthly\tsub.monthly\t1 Month\tStart\t3\t9.99\tUSD\tiPhone\tUS
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["123456789"], sourceReport: ["subscription-event"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["app"], "Test App")
    }

    func testSubscriberRecordsMatchAppAppleIDFilter() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscriber.tsv",
            source: .sales,
            reportType: "SUBSCRIBER",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tStandard Subscription Duration\tSubscribers\tBilling Retry\tGrace Period\tDeveloper Proceeds\tProceeds Currency\tDevice\tCountry
            2026-04-01\tTest App\t123456789\tPro Monthly\tsub.monthly\t1 Month\t12\t1\t0\t9.99\tUSD\tiPhone\tUS
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["123456789"], sourceReport: ["subscriber"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["app"], "Test App")
    }

    func testSubscriptionRecordsApplySKUFilter() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscription.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tSubscription Group ID\tStandard Subscription Duration\tDeveloper Proceeds\tProceeds Currency\tCustomer Currency\tDevice\tCountry\tActive Standard Price Subscriptions\tSubscribers
            2026-04-01\tTest App\t123456789\tPro Monthly\tsub.monthly\tgroup1\t1 Month\t9.99\tUSD\tUSD\tiPhone\tUS\t12\t12
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let matched = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sku: ["sub.monthly"], sourceReport: ["subscription"])
            ),
            offline: true
        )
        let missed = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sku: ["does-not-exist"], sourceReport: ["subscription"])
            ),
            offline: true
        )

        XCTAssertEqual(matched.data.records.count, 1)
        XCTAssertTrue(missed.data.records.isEmpty)
    }

    func testSubscriptionEventRecordsApplySubscriptionAppleIDAndSKUFilters() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscription-event-filters.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION_EVENT",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tStandard Subscription Duration\tEvent\tEvent Count\tDeveloper Proceeds\tProceeds Currency\tDevice\tCountry
            2026-04-01\tTest App\t123456789\tPro Monthly\tsub.monthly\t1 Month\tStart\t3\t9.99\tUSD\tiPhone\tUS
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let subscriptionID = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(subscription: ["sub.monthly"], sourceReport: ["subscription-event"])
            ),
            offline: true
        )
        let skuMatched = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sku: ["sub.monthly"], sourceReport: ["subscription-event"])
            ),
            offline: true
        )
        let skuMissed = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sku: ["does-not-exist"], sourceReport: ["subscription-event"])
            ),
            offline: true
        )

        XCTAssertEqual(subscriptionID.data.records.count, 1)
        XCTAssertEqual(skuMatched.data.records.count, 1)
        XCTAssertTrue(skuMissed.data.records.isEmpty)
    }

    func testReviewsAggregateKeepsDistinctSameNamedAppsSeparate() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [
                    try makeReview(id: "r1", appID: "1001", appName: "Same App", date: "2026-04-09", rating: 5, responded: false),
                    try makeReview(id: "r2", appID: "1002", appName: "Same App", date: "2026-04-09", rating: 4, responded: false)
                ]
            ),
            vendorNumber: "TEST_VENDOR"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-09"),
                groupBy: [.app]
            ),
            offline: true
        )

        XCTAssertEqual(
            Set(result.data.aggregates.compactMap { $0.group["app"] }),
            ["Same App (1001)", "Same App (1002)"]
        )
    }

    func testSubscriptionAggregateKeepsDistinctSameNamedAppsAndSubscriptionsSeparate() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscription-same-names.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-08",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tSubscription Group ID\tStandard Subscription Duration\tDeveloper Proceeds\tProceeds Currency\tCustomer Currency\tDevice\tCountry\tActive Standard Price Subscriptions\tSubscribers
            2026-04-08\tSame App\t1001\tMonthly\tsub.one\tgroup1\t1 Month\t10\tUSD\tUSD\tiPhone\tUS\t5\t5
            2026-04-08\tSame App\t1002\tMonthly\tsub.two\tgroup1\t1 Month\t14\tUSD\tUSD\tiPhone\tUS\t7\t7
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let appGrouped = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-08"),
                filters: QueryFilterSet(sourceReport: ["subscription"]),
                groupBy: [.app]
            ),
            offline: true
        )
        let subscriptionGrouped = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-08"),
                filters: QueryFilterSet(sourceReport: ["subscription"]),
                groupBy: [.subscription]
            ),
            offline: true
        )

        XCTAssertEqual(
            Set(appGrouped.data.aggregates.compactMap { $0.group["app"] }),
            ["Same App (1001)", "Same App (1002)"]
        )
        XCTAssertEqual(
            Set(subscriptionGrouped.data.aggregates.compactMap { $0.group["subscription"] }),
            ["Monthly (sub.one)", "Monthly (sub.two)"]
        )
    }

    func testSummarySalesAggregateGroupsSameParentAppIntoOneAppRow() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-same-parent-app.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-08",
            text: """
            Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tCustomer Price\tCustomer Currency
            2026-04-08\tCoin Pack A\tcoin.pack.a\t123456789\tIA1\t1\t0.99\tUSD\tUS\tiPhone\t3001\t1.0\t0.99\tUSD
            2026-04-08\tCoin Pack B\tcoin.pack.b\t123456789\tIA1\t2\t1.99\tUSD\tUS\tiPhone\t3002\t1.0\t1.99\tUSD
            """
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: [FXSeedRequest(dateKey: "2026-04-08", sourceCurrencyCode: "USD")]
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-08"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"]),
                groupBy: [.app]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 1)
        XCTAssertEqual(result.data.aggregates.first?.group["app"], "123456789")
        XCTAssertEqual(result.data.aggregates.first?.metrics["units"], 3)
    }

    func testSubscriberRecordsApplySubscriptionAppleIDAndSKUFilters() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "subscriber-filters.tsv",
            source: .sales,
            reportType: "SUBSCRIBER",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tStandard Subscription Duration\tSubscribers\tBilling Retry\tGrace Period\tDeveloper Proceeds\tProceeds Currency\tDevice\tCountry
            2026-04-01\tTest App\t123456789\tPro Monthly\tsub.monthly\t1 Month\t12\t1\t0\t9.99\tUSD\tiPhone\tUS
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let subscriptionID = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(subscription: ["sub.monthly"], sourceReport: ["subscriber"])
            ),
            offline: true
        )
        let skuMatched = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sku: ["sub.monthly"], sourceReport: ["subscriber"])
            ),
            offline: true
        )
        let skuMissed = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sku: ["does-not-exist"], sourceReport: ["subscriber"])
            ),
            offline: true
        )

        XCTAssertEqual(subscriptionID.data.records.count, 1)
        XCTAssertEqual(skuMatched.data.records.count, 1)
        XCTAssertTrue(skuMissed.data.records.isEmpty)
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

    func testReviewsRecordsFiltersByRatingAndResponseState() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [
                    makeReview(id: "r1", date: "2026-02-18", rating: 5, responded: true),
                    makeReview(id: "r2", date: "2026-02-18", rating: 5, responded: false),
                    makeReview(id: "r3", date: "2026-02-18", rating: 3, responded: true)
                ]
            )
        )
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        let ratingOnly = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(rating: [5])
            ),
            offline: true
        )
        XCTAssertEqual(ratingOnly.data.records.map(\.id).sorted(), ["r1", "r2"])

        let respondedOnly = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(responseState: "responded")
            ),
            offline: true
        )
        XCTAssertEqual(respondedOnly.data.records.map(\.id).sorted(), ["r1", "r3"])

        let combined = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(rating: [5], responseState: "responded")
            ),
            offline: true
        )
        XCTAssertEqual(combined.data.records.map(\.id), ["r1"])
    }

    func testReviewsOfflineLoadsOnlyConfiguredVendorCache() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [try makeReview(id: "vendor-a", date: "2026-02-18", rating: 5, responded: true)]
            ),
            vendorNumber: "VENDOR_A"
        )
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [try makeReview(id: "vendor-b", date: "2026-02-18", rating: 1, responded: false)]
            ),
            vendorNumber: "VENDOR_B"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "VENDOR_A")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18")
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.map(\.id), ["vendor-a"])
    }

    func testReviewsOfflineLoadsSingleScopedCacheWithoutConfiguredVendor() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [try makeReview(id: "vendor-a", date: "2026-02-18", rating: 5, responded: true)]
            ),
            vendorNumber: "VENDOR_A"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18")
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.map(\.id), ["vendor-a"])
    }

    func testReviewsOfflineRejectsAmbiguousLegacyCacheWhenOtherVendorScopedCacheExists() async throws {
        let cacheStore = try makeCacheStore()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try LocalFileSecurity.writePrivateData(
            try encoder.encode(
                CachedReviewsPayload(
                    fetchedAt: Date(),
                    reviews: [try makeReview(id: "legacy", date: "2026-02-18", rating: 5, responded: true)]
                )
            ),
            to: cacheStore.reviewsURL
        )
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [try makeReview(id: "vendor-b", date: "2026-02-18", rating: 1, responded: false)]
            ),
            vendorNumber: "VENDOR_B"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "VENDOR_A")
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .reviews,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-02-18")
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Cached reviews mix legacy latest.json"))
        }
    }

    func testReviewsRecordsTableDoesNotDuplicateRatingColumn() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [try makeReview(id: "r1", date: "2026-02-18", rating: 5, responded: false)]
            )
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18")
            ),
            offline: true
        )

        XCTAssertEqual(result.tableModel?.columns.filter { $0 == "rating" }.count, 1)
    }

    func testReviewsAggregateTableHidesRawRatingSumMetric() async throws {
        let cacheStore = try makeCacheStore()
        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [
                    try makeReview(id: "r1", date: "2026-02-18", rating: 5, responded: false),
                    try makeReview(id: "r2", date: "2026-02-18", rating: 3, responded: true)
                ]
            )
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .reviews,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-02-18")
            ),
            offline: true
        )

        XCTAssertFalse(result.tableModel?.columns.contains("rating") ?? true)
        XCTAssertTrue(result.tableModel?.columns.contains("averageRating") ?? false)
    }

    func testReviewsRejectUnsupportedResponseStateFilter() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .reviews,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(responseState: "pending")
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported reviews response-state: pending. Supported values: responded, unresponded."
            )
        }
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

    func testFinanceDefaultSourceReportIgnoresCachedFinanceDetail() async throws {
        let cacheStore = try makeCacheStore()
        let fixtureText = try fixture(named: "finance_detail_z1_2026-02.tsv")
        try recordReport(
            cacheStore: cacheStore,
            filename: "financial_z1_2025-11.tsv",
            source: .finance,
            reportType: "FINANCIAL",
            reportSubType: "Z1",
            reportDateKey: "2025-11-FINANCIAL-Z1",
            text: fixtureText
        )
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
            reportVariant: "FINANCIAL"
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
                groupBy: [.sourceReport]
            ),
            offline: true
        )

        XCTAssertEqual(result.source, ["financial"])
        XCTAssertEqual(result.data.aggregates.count, 1)
        XCTAssertEqual(result.data.aggregates.first?.group["sourceReport"], "financial")
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

    func testFinanceReportTypesDefaultsToFinancialWhenSourceReportIsOmitted() throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())

        XCTAssertEqual(
            engine.financeReportTypes(for: []),
            [.financial]
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

    func testSalesAggregateRejectsMixedSourceReportsWithoutSeparatingGroupBy() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-04-01"),
                    filters: QueryFilterSet(sourceReport: ["summary-sales", "subscription"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Sales aggregate and compare queries cannot combine multiple source-report families unless grouped by sourceReport or reportType."
            )
        }
    }

    func testSalesAggregateAllowsMixedSourceReportsWhenGroupedBySourceReport() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-mixed-summary.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
            2026-04-01\t2026-04-01\tTest App\ttest.app\t123456789\t1F\t1\t10\tUSD\tUS\tiPhone\t123456789\t1.0\t\t\tios\t10\tUSD
            """
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-mixed-subscription.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tSubscription Group ID\tStandard Subscription Duration\tDeveloper Proceeds\tProceeds Currency\tCustomer Currency\tDevice\tCountry\tActive Standard Price Subscriptions\tSubscribers
            2026-04-01\tTest App\t123456789\tPro Monthly\tsub.monthly\tgroup1\t1 Month\t5\tUSD\tUSD\tiPhone\tUS\t12\t12
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["summary-sales", "subscription"]),
                groupBy: [.sourceReport]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 2)
        XCTAssertEqual(result.data.aggregates.first(where: { $0.group["sourceReport"] == "summary-sales" })?.metrics["proceeds"], 10)
        XCTAssertEqual(result.data.aggregates.first(where: { $0.group["sourceReport"] == "subscription" })?.metrics["proceeds"], 5)
    }

    func testFinanceAggregateRejectsMixedSourceReportsWithoutSeparatingGroupBy() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .finance,
                    operation: .aggregate,
                    time: QueryTimeSelection(fiscalMonth: "2025-11"),
                    filters: QueryFilterSet(sourceReport: ["financial", "finance-detail"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Finance aggregate and compare queries cannot combine financial and finance-detail unless grouped by sourceReport or reportType."
            )
        }
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

    func testAnalyticsEngagementRejectsVersionFilter() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .analytics,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-04-01"),
                    filters: QueryFilterSet(version: ["1.0"], sourceReport: ["engagement"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unsupported analytics filter"))
            XCTAssertTrue(error.localizedDescription.contains("app-version"))
        }
    }

    func testAnalyticsEngagementRejectsVersionGroupBy() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .analytics,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-04-01"),
                    filters: QueryFilterSet(sourceReport: ["engagement"]),
                    groupBy: [.version]
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unsupported analytics group-by"))
            XCTAssertTrue(error.localizedDescription.contains("version"))
        }
    }

    func testAnalyticsRecordsWarnsWhenRequestIsStillMissingAfterCreation() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "1",
                              "attributes": {
                                "name": "Hive",
                                "bundleId": "studio.bunny.hive"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if (request.httpMethod ?? "GET") == "POST", url.path == "/v1/analyticsReportRequests" {
                return (
                    HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": {
                            "id": "request-1",
                            "attributes": {
                              "accessType": "ONGOING",
                              "stoppedDueToInactivity": false
                            }
                          }
                        }
                        """.utf8
                    )
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[]}".utf8)
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertTrue(result.data.records.isEmpty)
        XCTAssertTrue(result.warnings.contains { $0.code == "analytics-request-missing" })
    }

    func testAnalyticsRecordsWarnsWhenProcessingDateHasNoInstances() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "1",
                              "attributes": {
                                "name": "Hive",
                                "bundleId": "studio.bunny.hive"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "request-1",
                              "attributes": {
                                "accessType": "ONE_TIME_SNAPSHOT",
                                "stoppedDueToInactivity": false
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path.contains("/analyticsReportRequests/"), url.path.hasSuffix("/reports") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "report-1",
                              "attributes": {
                                "name": "App Sessions",
                                "category": "APP_USAGE"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path.contains("/analyticsReports/"), url.path.hasSuffix("/instances") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[]}".utf8)
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertTrue(result.data.records.isEmpty)
        XCTAssertTrue(
            result.warnings.contains {
                $0.code == "analytics-instance-missing" && $0.message.contains("2026-02-18")
            },
            "Warnings: \(result.warnings)"
        )
    }

    func testAnalyticsRecordsParsesQuotedCSVFields() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-quoted.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
            2026-04-01,"My App, Pro",123456789,US,iPhone,iOS,10
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )

        let record = try XCTUnwrap(result.data.records.first)
        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(record.dimensions["app"], "My App, Pro")
        XCTAssertEqual(record.dimensions["appAppleIdentifier"], "123456789")
        XCTAssertEqual(record.metrics["sessions"], 10)
    }

    func testAnalyticsGroupBySourceReportUsesCanonicalQueryIdentifier() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-acquisition.csv",
            source: .analytics,
            reportType: "App Store Downloads",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,App Apple Identifier,App Version,Territory,Device,Platform Version,Count
            2026-04-01,My App,123456789,1.0,US,iPhone,iOS 18.0,10
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["acquisition"]),
                groupBy: [.sourceReport]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.first?.group["sourceReport"], "acquisition")
    }

    func testAnalyticsAggregateKeepsDistinctSameNamedAppsSeparate() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-same-name.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
            2026-04-01,Same App,1001,US,iPhone,iOS,10
            2026-04-01,Same App,1002,US,iPhone,iOS,20
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"]),
                groupBy: [.app]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 2)
        XCTAssertEqual(
            Set(result.data.aggregates.compactMap { $0.group["app"] }),
            ["Same App (1001)", "Same App (1002)"]
        )
    }

    func testAnalyticsOnlineSyncKeepsSegmentsWithSharedChecksumFromDifferentApps() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "app-1",
                              "attributes": { "name": "Same App", "bundleId": "com.example.one" }
                            },
                            {
                              "id": "app-2",
                              "attributes": { "name": "Same App", "bundleId": "com.example.two" }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/apps/app-1/analyticsReportRequests" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/apps/app-2/analyticsReportRequests" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-2\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"report-1\",\"attributes\":{\"name\":\"App Sessions\",\"category\":\"APP_USAGE\"}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-2/reports" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"report-2\",\"attributes\":{\"name\":\"App Sessions\",\"category\":\"APP_USAGE\"}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-04-01")
            }
            if url.path == "/v1/analyticsReports/report-2/instances" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"instance-2\",\"attributes\":{\"granularity\":\"DAILY\",\"processingDate\":\"2026-04-01\"}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://downloads.example.com/app-1.csv?token=a")
            }
            if url.path == "/v1/analyticsReportInstances/instance-2/segments" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"segment-2\",\"attributes\":{\"checksum\":\"shared-checksum\",\"sizeInBytes\":128,\"url\":\"https://downloads.example.com/app-2.csv?token=b\"}}]}".utf8)
                )
            }
            if url.host == "downloads.example.com", url.path == "/app-1.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
                    2026-04-01,Same App,1001,US,iPhone,iOS,10
                    """
                )
            }
            if url.host == "downloads.example.com", url.path == "/app-2.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
                    2026-04-01,Same App,1002,US,iPhone,iOS,20
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 2)
        XCTAssertEqual(
            Set(result.data.records.compactMap { $0.dimensions["appAppleIdentifier"] }),
            ["1001", "1002"]
        )
    }

    func testAnalyticsCompareOnlineSyncsPreviousWindow() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"app-1\",\"attributes\":{\"name\":\"Hive\",\"bundleId\":\"studio.bunny.hive\"}}]}".utf8)
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                let processingDate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "filter[processingDate]" })?
                    .value ?? ""
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "instance-\(processingDate)",
                              "attributes": {
                                "granularity": "DAILY",
                                "processingDate": "\(processingDate)"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/analyticsReportInstances/instance-2026-04-01/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/previous.csv")
            }
            if url.path == "/v1/analyticsReportInstances/instance-2026-04-02/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/current.csv")
            }
            if url.host == "download.example.com", url.path == "/previous.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,Territory,Device,Platform,Sessions
                    2026-04-01,Hive,US,iPhone,iOS,10
                    """
                )
            }
            if url.host == "download.example.com", url.path == "/current.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,Territory,Device,Platform,Sessions
                    2026-04-02,Hive,US,iPhone,iOS,20
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .compare,
                time: QueryTimeSelection(datePT: "2026-04-02"),
                compare: .custom,
                compareTime: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.comparisons.count, 1)
        let row = result.data.comparisons[0]
        XCTAssertEqual(row.metrics["sessions"]?.current, 20)
        XCTAssertEqual(row.metrics["sessions"]?.previous, 10)
    }

    func testAnalyticsOnlineRecordsMatchBundleIDFilter() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"app-1\",\"attributes\":{\"name\":\"Hive\",\"bundleId\":\"studio.bunny.hive\"}}]}".utf8)
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-04-01")
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/bundle-filter.csv")
            }
            if url.host == "download.example.com", url.path == "/bundle-filter.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
                    2026-04-01,Hive,6502647802,US,iPhone,iOS,12
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["studio.bunny.hive"], sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["app"], "Hive")
        XCTAssertFalse(result.warnings.contains(where: { $0.code == "analytics-no-apps" }))
    }

    func testAnalyticsOfflineRecordsMatchBundleIDFilter() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-bundle-filter.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            appID: "app-1",
            bundleID: "studio.bunny.hive",
            text: """
            Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
            2026-04-01,Hive,6502647802,US,iPhone,iOS,12
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["studio.bunny.hive"], sourceReport: ["usage"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["app"], "Hive")
    }

    func testAnalyticsOnlineBundleIDFilterDoesNotLeakSameNamedApps() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            { "id": "1001", "attributes": { "name": "Same App", "bundleId": "com.example.one" } },
                            { "id": "1002", "attributes": { "name": "Same App", "bundleId": "com.example.two" } }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/apps/1001/analyticsReportRequests" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-04-01")
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/same-name-filter.csv")
            }
            if url.host == "download.example.com", url.path == "/same-name-filter.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
                    2026-04-01,Same App,1001,US,iPhone,iOS,12
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["com.example.one"], sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["appAppleIdentifier"], "1001")
    }

    func testAnalyticsOnlineBundleIDFilterDoesNotLeakSameNamedFreshCacheRows() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "same-name-fresh-cache.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            appID: "1002",
            bundleID: "com.example.two",
            text: """
            Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
            2026-04-01,Same App,1002,US,iPhone,iOS,99
            """,
            fetchedAt: Date()
        )

        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            { "id": "1001", "attributes": { "name": "Same App", "bundleId": "com.example.one" } },
                            { "id": "1002", "attributes": { "name": "Same App", "bundleId": "com.example.two" } }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/apps/1001/analyticsReportRequests" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-04-01")
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/same-name-filter-fresh.csv")
            }
            if url.host == "download.example.com", url.path == "/same-name-filter-fresh.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
                    2026-04-01,Same App,1001,US,iPhone,iOS,12
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["com.example.one"], sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["appAppleIdentifier"], "1001")
        XCTAssertEqual(result.data.records.first?.metrics["sessions"], 12)
    }

    func testAnalyticsOnlineAppIDFilterDoesNotLeakSameNamedFreshCacheRows() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "same-name-fresh-cache-id.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            appID: "1002",
            bundleID: "com.example.two",
            text: """
            Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
            2026-04-01,Same App,1002,US,iPhone,iOS,99
            """,
            fetchedAt: Date()
        )

        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            { "id": "1001", "attributes": { "name": "Same App", "bundleId": "com.example.one" } },
                            { "id": "1002", "attributes": { "name": "Same App", "bundleId": "com.example.two" } }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/apps/1001/analyticsReportRequests" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-04-01")
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/same-name-filter-id.csv")
            }
            if url.host == "download.example.com", url.path == "/same-name-filter-id.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
                    2026-04-01,Same App,1001,US,iPhone,iOS,12
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["1001"], sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["appAppleIdentifier"], "1001")
        XCTAssertEqual(result.data.records.first?.metrics["sessions"], 12)
    }

    func testAnalyticsOnlineQueryIgnoresStaleCacheWhenFreshReportIsMissing() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "stale-analytics.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,Territory,Device,Platform,Sessions
            2026-04-01,Stale App,US,iPhone,iOS,42
            """,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )

        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"app-1\",\"attributes\":{\"name\":\"Hive\",\"bundleId\":\"studio.bunny.hive\"}}]}".utf8)
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[{\"id\":\"request-1\",\"attributes\":{\"accessType\":\"ONGOING\",\"stoppedDueToInactivity\":false}}]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-1/reports" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[]}".utf8)
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertTrue(result.data.records.isEmpty)
        XCTAssertTrue(result.warnings.contains(where: { $0.code == "analytics-report-missing" }))
    }

    func testAnalyticsRecordsRejectRowsWithoutDate() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-no-date.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            App Name,App Apple Identifier,Territory,Device,Platform,Sessions
            Test App,123456789,US,iPhone,iOS,42
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let firstResult = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )
        let secondResult = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-07"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )

        XCTAssertTrue(firstResult.data.records.isEmpty)
        XCTAssertTrue(secondResult.data.records.isEmpty)
    }

    func testAnalyticsRecordsTreatNumericAppIDAndVersionAsDimensions() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-dimensions.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,App Apple Identifier,App Version,Territory,Device,Platform,Sessions
            2026-04-01,My App,123456789,1.0,US,iPhone,iOS,10
            """
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let appFiltered = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(app: ["123456789"], sourceReport: ["usage"])
            ),
            offline: true
        )
        XCTAssertEqual(appFiltered.data.records.count, 1)

        let versionFiltered = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(version: ["1.0"], sourceReport: ["usage"])
            ),
            offline: true
        )
        XCTAssertEqual(versionFiltered.data.records.count, 1)

        let grouped = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"]),
                groupBy: [.version]
            ),
            offline: true
        )
        let row = try XCTUnwrap(grouped.data.aggregates.first)
        XCTAssertEqual(row.group["version"], "1.0")
        XCTAssertEqual(row.metrics["sessions"], 10)
        XCTAssertNil(row.metrics["app version"])
        XCTAssertNil(row.metrics["app apple identifier"])
    }

    func testAnalyticsOfflineLoadsLegacyUnscopedCacheForConfiguredVendor() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-09",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-09\tTest App\t123456789\t10
            """,
            vendorNumber: ""
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-09"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.metrics["sessions"], 10)
    }

    func testAnalyticsOfflineRejectsAmbiguousLegacyCacheWhenOtherVendorEntriesExist() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-09",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-09\tLegacy App\t123456789\t10
            """,
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-other-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-09",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-09\tOther Vendor App\t987654321\t5
            """,
            vendorNumber: "VENDOR_B"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .analytics,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-04-09"),
                    filters: QueryFilterSet(sourceReport: ["usage"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("legacy unscoped entries"))
        }
    }

    func testAnalyticsOfflineMergesLegacyUnscopedCacheWhenScopedVendorCacheExists() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-08",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-08\tLegacy App\t123456789\t10
            """,
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-current-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-09",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-09\tCurrent App\t987654321\t5
            """,
            vendorNumber: "TEST_VENDOR"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(startDatePT: "2026-04-08", endDatePT: "2026-04-09"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 2)
        XCTAssertEqual(
            Set(result.data.records.compactMap { $0.dimensions["app"] }),
            ["Legacy App", "Current App"]
        )
    }

    func testAnalyticsOfflineLoadsLegacyHistoryWhenOtherScopedVendorEntriesAreOutsideQueryDates() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-01\tLegacy App\t123456789\t10
            """,
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-current-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-02",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-02\tCurrent App\t987654321\t5
            """,
            vendorNumber: "TEST_VENDOR"
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-other-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-03",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-03\tOther Vendor App\t555555555\t7
            """,
            vendorNumber: "VENDOR_B"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(startDatePT: "2026-04-01", endDatePT: "2026-04-02"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 2)
        XCTAssertEqual(
            Set(result.data.records.compactMap { $0.dimensions["app"] }),
            ["Legacy App", "Current App"]
        )
    }

    func testAnalyticsOfflineAllowsScopedQueryWhenLegacyAndOtherVendorHistoryAreOutsideRequestedDates() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-01\tLegacy App\t123456789\t10
            """,
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-current-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-02",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-02\tCurrent App\t987654321\t5
            """,
            vendorNumber: "TEST_VENDOR"
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-other-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-03",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-03\tOther Vendor App\t555555555\t7
            """,
            vendorNumber: "VENDOR_B"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-02"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.dimensions["app"], "Current App")
        XCTAssertEqual(result.data.records.first?.metrics["sessions"], 5)
    }

    func testSalesOfflinePrefersScopedCacheOverLegacyDuplicate() async throws {
        let cacheStore = try makeCacheStore()
        let salesText = """
        Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
        2026-04-09\t2026-04-09\tHive App\thive.app\t\t1F\t1\t5\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t5\tUSD
        """
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-legacy.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-09",
            text: salesText,
            fetchedAt: Date(timeIntervalSince1970: 1),
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales-scoped.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-04-09",
            text: salesText,
            fetchedAt: Date(timeIntervalSince1970: 2),
            vendorNumber: "TEST_VENDOR"
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: [FXSeedRequest(dateKey: "2026-04-09", sourceCurrencyCode: "USD")]
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-09"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 1)
        XCTAssertEqual(result.data.aggregates.first?.metrics["proceeds"] ?? 0, 5, accuracy: 0.0001)
        XCTAssertEqual(result.data.aggregates.first?.metrics["units"] ?? 0, 1, accuracy: 0.0001)
    }

    func testAnalyticsOfflineRejectsLegacyAndScopedCacheWhenVendorNumberIsUnset() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-09",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-09\tLegacy App\t123456789\t10
            """,
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-current-vendor.tsv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-09",
            text: """
            Date\tApp Name\tApp Apple Identifier\tSessions
            2026-04-09\tCurrent App\t987654321\t5
            """,
            vendorNumber: "TEST_VENDOR"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .analytics,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-04-09"),
                    filters: QueryFilterSet(sourceReport: ["usage"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("mix legacy unscoped entries with vendor-tagged entries"))
        }
    }

    func testAnalyticsAggregateKeepsLatestAnalyticsRowsWithoutDoubleCountingOldSegments() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-old.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,Territory,Device,Platform,Sessions
            2026-04-01,My App,US,iPhone,iOS,10
            """,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        let latestBatchTimestamp = Date(timeIntervalSince1970: 60)
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-new-a.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,Territory,Device,Platform,Sessions
            2026-04-01,My App,US,iPhone,iOS,7
            """,
            fetchedAt: latestBatchTimestamp
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-new-b.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: """
            Date,App Name,Territory,Device,Platform,Sessions
            2026-04-01,Other App,US,iPhone,iOS,5
            """,
            fetchedAt: latestBatchTimestamp
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"]),
                groupBy: [.app]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 2)
        XCTAssertEqual(
            result.data.aggregates.first(where: { $0.group["app"] == "My App" })?.metrics["sessions"],
            7
        )
        XCTAssertEqual(
            result.data.aggregates.first(where: { $0.group["app"] == "Other App" })?.metrics["sessions"],
            5
        )
    }

    func testAnalyticsOfflineDoesNotDoubleCountScopedAndLegacyCopiesOfSameRow() async throws {
        let cacheStore = try makeCacheStore()
        let csv = """
        Date,App Name,App Apple Identifier,Territory,Device,Platform,Sessions
        2026-04-01,Hive,6502647802,US,iPhone,iOS,12
        """
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-legacy.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            text: csv,
            fetchedAt: Date(timeIntervalSince1970: 1),
            vendorNumber: ""
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "analytics-scoped.csv",
            source: .analytics,
            reportType: "App Sessions",
            reportSubType: "SEGMENT",
            reportDateKey: "2026-04-01",
            appID: "app-1",
            bundleID: "studio.bunny.hive",
            text: csv,
            fetchedAt: Date(timeIntervalSince1970: 2),
            vendorNumber: "TEST_VENDOR"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "TEST_VENDOR")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"]),
                groupBy: [.app]
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.count, 1)
        XCTAssertEqual(result.data.aggregates.first?.metrics["sessions"], 12)
    }

    func testAnalyticsRecordsPrefersOngoingRequestForDateQueries() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "1",
                              "attributes": {
                                "name": "Hive",
                                "bundleId": "studio.bunny.hive"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "request-ongoing",
                              "attributes": {
                                "accessType": "ONGOING",
                                "stoppedDueToInactivity": false
                              }
                            },
                            {
                              "id": "request-snapshot",
                              "attributes": {
                                "accessType": "ONE_TIME_SNAPSHOT",
                                "stoppedDueToInactivity": false
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-ongoing/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReportRequests/request-snapshot/reports" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-04-01")
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/ongoing.csv")
            }
            if url.host == "download.example.com", url.path == "/ongoing.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,Territory,Device,Platform,Sessions
                    2026-04-01,Hive,US,iPhone,iOS,10
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(datePT: "2026-04-01"),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.metrics["sessions"], 10)
    }

    func testAnalyticsRecordsPrefersSnapshotRequestForYearQueries() async throws {
        let cacheStore = try makeCacheStore()
        let engine = makeOnlineAnalyticsEngine(cacheStore: cacheStore) { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "1",
                              "attributes": {
                                "name": "Hive",
                                "bundleId": "studio.bunny.hive"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path.hasSuffix("/analyticsReportRequests") {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "request-ongoing",
                              "attributes": {
                                "accessType": "ONGOING",
                                "stoppedDueToInactivity": false
                              }
                            },
                            {
                              "id": "request-snapshot",
                              "attributes": {
                                "accessType": "ONE_TIME_SNAPSHOT",
                                "stoppedDueToInactivity": false
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }
            if url.path == "/v1/analyticsReportRequests/request-snapshot/reports" {
                return Self.analyticsReportsResponse(url: url)
            }
            if url.path == "/v1/analyticsReportRequests/request-ongoing/reports" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"data\":[]}".utf8)
                )
            }
            if url.path == "/v1/analyticsReports/report-1/instances" {
                return Self.analyticsInstancesResponse(url: url, processingDate: "2026-12-05", granularity: "MONTHLY")
            }
            if url.path == "/v1/analyticsReportInstances/instance-1/segments" {
                return Self.analyticsSegmentsResponse(url: url, downloadURL: "https://download.example.com/snapshot.csv")
            }
            if url.host == "download.example.com", url.path == "/snapshot.csv" {
                return Self.analyticsSegmentDownload(
                    url: url,
                    csv: """
                    Date,App Name,Territory,Device,Platform,Sessions
                    2026-12-05,Hive,US,iPhone,iOS,99
                    """
                )
            }
            throw URLError(.unsupportedURL)
        }

        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeSelection(year: 2026),
                filters: QueryFilterSet(sourceReport: ["usage"])
            ),
            offline: false
        )

        XCTAssertEqual(result.data.records.count, 1)
        XCTAssertEqual(result.data.records.first?.metrics["sessions"], 99)
    }

    func testSalesRejectsUnsupportedRatingFilter() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(rating: [5])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported sales filter(s): rating. Supported filters: app, app-version, currency, device, sku, source-report, subscription, territory."
            )
        }
    }

    func testSalesRejectsUnsupportedGroupBy() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(sourceReport: ["subscription"]),
                    groupBy: [.rating]
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported sales group-by value(s): rating. Supported values: app, currency, day, device, fiscalMonth, month, reportType, sku, sourceReport, subscription, territory, week."
            )
        }
    }

    func testFinanceRejectsUnsupportedGroupBy() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .finance,
                    operation: .aggregate,
                    time: QueryTimeSelection(fiscalMonth: "2025-11"),
                    filters: QueryFilterSet(sourceReport: ["finance-detail"]),
                    groupBy: [.app]
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported finance group-by value(s): app. Supported values: currency, day, fiscalMonth, month, reportType, sku, sourceReport, territory, week."
            )
        }
    }

    func testFinanceRejectsUnsupportedAppFilter() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .finance,
                    operation: .records,
                    time: QueryTimeSelection(fiscalMonth: "2025-11"),
                    filters: QueryFilterSet(app: ["123456789"], sourceReport: ["finance-detail"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported finance filter(s): app. Supported filters: currency, sku, source-report, territory."
            )
        }
    }

    func testFinanceRejectsDateSelectorInQuerySpec() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .finance,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-01-15")
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported finance time selector(s): datePT. Supported selectors: fiscalMonth, fiscalYear, rangePreset, year."
            )
        }
    }

    func testSalesRejectsFiscalMonthSelectorInQuerySpec() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .records,
                    time: QueryTimeSelection(fiscalMonth: "2026-02")
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "Unsupported sales time selector(s): fiscalMonth. Supported selectors: datePT, endDatePT, rangePreset, startDatePT, year."
            )
        }
    }

    func testAggregateRejectsCompareOptions() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    compare: .previousPeriod
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "compare and compareTime are only supported for compare operations."
            )
        }
    }

    func testCompareTimeRequiresCustomCompareMode() async throws {
        let cacheStore = try makeCacheStore()
        let engine = AnalyticsEngine(cacheStore: cacheStore)

        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .compare,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    compareTime: QueryTimeSelection(datePT: "2026-02-17")
                ),
                offline: true
            )
        ) { error in
            XCTAssertEqual(
                (error as? AnalyticsEngineError)?.errorDescription,
                "compareTime requires compare=custom."
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

    func testSalesCurrencyFilterMatchesReportedCurrencyOnly() async throws {
        let cacheStore = try makeCacheStore()
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_currency_filter.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: """
            Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
            2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t10\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t68\tCNY
            """
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: [FXSeedRequest(dateKey: "2026-02-18", sourceCurrencyCode: "USD")]
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        let filtered = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(currency: ["CNY"], sourceReport: ["summary-sales"]),
                groupBy: [.currency]
            ),
            offline: true
        )

        XCTAssertTrue(filtered.data.aggregates.isEmpty)
    }

    func testSalesAggregateFailsWhenCachedReportPermissionsAreTooBroad() async throws {
        let cacheStore = try makeCacheStore()
        let fileURL = try recordReport(
            cacheStore: cacheStore,
            filename: "subscription_2026-02-18.tsv",
            source: .sales,
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: try fixture(named: "subscription_2026-02-18.tsv")
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(sourceReport: ["subscription"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue((error as? LocalFileSecurityError)?.errorDescription?.contains("chmod 600") == true)
        }
    }

    func testSalesSummaryReportsRejectSubscriptionFilter() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-04-01"),
                    filters: QueryFilterSet(subscription: ["sub.monthly"], sourceReport: ["summary-sales"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unsupported sales filter"))
            XCTAssertTrue(error.localizedDescription.contains("subscription"))
        }
    }

    func testSubscriptionReportsRejectVersionFilter() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .records,
                    time: QueryTimeSelection(datePT: "2026-04-01"),
                    filters: QueryFilterSet(version: ["9.9"], sourceReport: ["subscription"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Unsupported sales filter"))
            XCTAssertTrue(error.localizedDescription.contains("app-version"))
        }
    }

    func testSalesAggregateUsesConfiguredVendorOnly() async throws {
        let cacheStore = try makeCacheStore()
        let vendorAText = """
        Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
        2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t10\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t10\tUSD
        """
        let vendorBText = """
        Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
        2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t20\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t20\tUSD
        """
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_vendor_a.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: vendorAText,
            vendorNumber: "VENDOR_A"
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_vendor_b.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: vendorBText,
            vendorNumber: "VENDOR_B"
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: [FXSeedRequest(dateKey: "2026-02-18", sourceCurrencyCode: "USD")]
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore, vendorNumber: "VENDOR_A")
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeSelection(datePT: "2026-02-18"),
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.data.aggregates.first?.metrics["proceeds"] ?? 0, 10, accuracy: 0.0001)
    }

    func testSalesAggregateFailsWhenCacheContainsMultipleVendorsWithoutConfiguredVendor() async throws {
        let cacheStore = try makeCacheStore()
        let salesText = """
        Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
        2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t1\t10\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t10\tUSD
        """
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_vendor_a.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: salesText,
            vendorNumber: "VENDOR_A"
        )
        try recordReport(
            cacheStore: cacheStore,
            filename: "sales_vendor_b.tsv",
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            reportDateKey: "2026-02-18",
            text: salesText,
            vendorNumber: "VENDOR_B"
        )

        let engine = AnalyticsEngine(cacheStore: cacheStore)
        await XCTAssertThrowsErrorAsync(
            try await engine.execute(
                spec: DataQuerySpec(
                    dataset: .sales,
                    operation: .aggregate,
                    time: QueryTimeSelection(datePT: "2026-02-18"),
                    filters: QueryFilterSet(sourceReport: ["summary-sales"])
                ),
                offline: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("multiple vendor numbers"))
        }
    }

    func testMonthOverMonthComparisonPreservesRangeLengthAcrossMonthBoundary() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .compare,
                time: QueryTimeSelection(startDatePT: "2026-03-30", endDatePT: "2026-03-31"),
                compare: .monthOverMonth,
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.comparison?.previous.startDatePT, "2026-02-27")
        XCTAssertEqual(result.comparison?.previous.endDatePT, "2026-02-28")
    }

    func testMonthOverMonthComparisonKeepsFullPreviousMonthWindow() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .compare,
                time: QueryTimeSelection(startDatePT: "2026-03-01", endDatePT: "2026-03-31"),
                compare: .monthOverMonth,
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.comparison?.previous.startDatePT, "2026-02-01")
        XCTAssertEqual(result.comparison?.previous.endDatePT, "2026-02-28")
    }

    func testMonthOverMonthComparisonKeepsLongerPreviousMonthWindow() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .compare,
                time: QueryTimeSelection(startDatePT: "2026-02-01", endDatePT: "2026-02-28"),
                compare: .monthOverMonth,
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.comparison?.previous.startDatePT, "2026-01-01")
        XCTAssertEqual(result.comparison?.previous.endDatePT, "2026-01-31")
    }

    func testYearOverYearComparisonKeepsFullPreviousYearWindow() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .compare,
                time: QueryTimeSelection(startDatePT: "2024-01-01", endDatePT: "2024-12-31"),
                compare: .yearOverYear,
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.comparison?.previous.startDatePT, "2023-01-01")
        XCTAssertEqual(result.comparison?.previous.endDatePT, "2023-12-31")
    }

    func testYearOverYearComparisonKeepsLeapDayInFullPreviousMonthWindow() async throws {
        let engine = AnalyticsEngine(cacheStore: try makeCacheStore())
        let result = try await engine.execute(
            spec: DataQuerySpec(
                dataset: .sales,
                operation: .compare,
                time: QueryTimeSelection(startDatePT: "2025-02-01", endDatePT: "2025-02-28"),
                compare: .yearOverYear,
                filters: QueryFilterSet(sourceReport: ["summary-sales"])
            ),
            offline: true
        )

        XCTAssertEqual(result.comparison?.previous.startDatePT, "2024-02-01")
        XCTAssertEqual(result.comparison?.previous.endDatePT, "2024-02-29")
    }

    private func makeCacheStore() throws -> CacheStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()
        return cacheStore
    }

    @discardableResult
    private func recordReport(
        cacheStore: CacheStore,
        filename: String,
        source: ReportSource,
        reportType: String,
        reportSubType: String,
        reportDateKey: String,
        appID: String? = nil,
        bundleID: String? = nil,
        text: String,
        fetchedAt: Date = Date(),
        vendorNumber: String = "TEST_VENDOR"
    ) throws -> URL {
        let fileURL = cacheStore.reportsDirectory.appendingPathComponent(filename)
        try LocalFileSecurity.writePrivateData(Data(text.utf8), to: fileURL)
        _ = try cacheStore.record(
            report: DownloadedReport(
                source: source,
                reportType: reportType,
                reportSubType: reportSubType,
                queryHash: filename,
                reportDateKey: reportDateKey,
                vendorNumber: vendorNumber,
                appID: appID,
                bundleID: bundleID,
                fileURL: fileURL,
                rawText: text
            ),
            fetchedAt: fetchedAt
        )
        return fileURL
    }

    private func writeFXRates(cacheStore: CacheStore, json: String) throws {
        try LocalFileSecurity.writePrivateData(Data(json.utf8), to: cacheStore.fxRatesURL)
    }

    private func makeOnlineAnalyticsEngine(
        cacheStore: CacheStore,
        requestHandler: @escaping @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)
    ) -> AnalyticsEngine {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnalyticsStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        AnalyticsStubURLProtocol.requestHandler = requestHandler
        let client = ASCClient(session: session, tokenProvider: { "TEST_TOKEN" })
        let downloader = ReportDownloader(
            client: client,
            credentialsProvider: {
                Credentials(
                    issuerID: "TEST_ISSUER",
                    keyID: "TEST_KEY",
                    vendorNumber: "TEST_VENDOR",
                    privateKeyPEM: "TEST_PEM"
                )
            },
            reportsRootDirectoryURL: cacheStore.reportsDirectory
        )
        return AnalyticsEngine(cacheStore: cacheStore, client: client, downloader: downloader, vendorNumber: "TEST_VENDOR")
    }

    private static func analyticsReportsResponse(url: URL) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(
                """
                {
                  "data": [
                    {
                      "id": "report-1",
                      "attributes": {
                        "name": "App Sessions",
                        "category": "APP_USAGE"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    private static func analyticsInstancesResponse(
        url: URL,
        processingDate: String,
        granularity: String = "DAILY"
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(
                """
                {
                  "data": [
                    {
                      "id": "instance-1",
                      "attributes": {
                        "granularity": "\(granularity)",
                        "processingDate": "\(processingDate)"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    private static func analyticsSegmentsResponse(
        url: URL,
        downloadURL: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(
                """
                {
                  "data": [
                    {
                      "id": "segment-1",
                      "attributes": {
                        "checksum": "checksum-1",
                        "sizeInBytes": 128,
                        "url": "\(downloadURL)"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    private static func analyticsSegmentDownload(
        url: URL,
        csv: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(csv.utf8)
        )
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
        try makeReview(
            id: id,
            appID: "6502647802",
            appName: "Hive",
            date: date,
            rating: rating,
            responded: responded
        )
    }

    private func makeReview(
        id: String,
        appID: String,
        appName: String,
        date: String,
        rating: Int,
        responded: Bool
    ) throws -> ASCLatestReview {
        ASCLatestReview(
            id: id,
            appID: appID,
            appName: appName,
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

private final class AnalyticsStubURLProtocol: URLProtocol, @unchecked Sendable {
    static nonisolated(unsafe) var requestHandler: (@Sendable (URLRequest) async throws -> (HTTPURLResponse, Data))?

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        loadingTask = Task {
            do {
                let (response, data) = try await handler(request)
                guard Task.isCancelled == false else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard Task.isCancelled == false else { return }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}
