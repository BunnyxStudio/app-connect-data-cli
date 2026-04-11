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

final class BinarySmokeTests: XCTestCase {
    func testVersionFlagPrintsVersion() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["--version"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("0.1.9"), result.output)
    }

    func testCapabilitiesListRunsWithoutCredentials() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["capabilities", "list", "--output", "table"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("sales"))
        XCTAssertTrue(result.output.contains("analytics"))
    }

    func testCapabilitiesJSONUsesQuerySpecFilterNames() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["capabilities", "list", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        let descriptors = try JSONDecoder().decode([CapabilityDescriptor].self, from: Data(result.output.utf8))
        let sales = try XCTUnwrap(descriptors.first(where: { $0.name == "sales" }))
        let analytics = try XCTUnwrap(descriptors.first(where: { $0.name == "analytics" }))
        XCTAssertTrue(sales.filterSupport.contains("version"))
        XCTAssertFalse(sales.filterSupport.contains("app-version"))
        XCTAssertTrue(analytics.filterSupport.contains("version"))
        XCTAssertFalse(analytics.filterSupport.contains("app-version"))
    }

    func testFinanceHelpOnlyShowsFinanceOptions() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["finance", "aggregate", "--help"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("--fiscal-month"), result.output)
        XCTAssertTrue(result.output.contains("--territory"), result.output)
        XCTAssertFalse(result.output.contains("--date"), result.output)
        XCTAssertFalse(result.output.contains("App filter"), result.output)
        XCTAssertFalse(result.output.contains("Version filter"), result.output)
    }

    func testReviewsHelpOnlyShowsReviewFilters() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["reviews", "records", "--help"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("--rating"), result.output)
        XCTAssertTrue(result.output.contains("--response-state"), result.output)
        XCTAssertFalse(result.output.contains("Version filter"), result.output)
        XCTAssertFalse(result.output.contains("SKU filter"), result.output)
        XCTAssertFalse(result.output.contains("Subscription filter"), result.output)
    }

    func testSalesHelpUsesAppVersionFilterName() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["sales", "aggregate", "--help"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("--app-version"), result.output)
        XCTAssertFalse(result.output.contains("--version <version>"), result.output)
    }

    func testSalesSubcommandVersionFlagPrintsCLIInfo() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["sales", "aggregate", "--version"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("0.1.9"), result.output)
    }

    func testAnalyticsHelpUsesAppVersionFilterName() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["analytics", "aggregate", "--help"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("--app-version"), result.output)
        XCTAssertFalse(result.output.contains("--version <version>"), result.output)
    }

    func testQueryRunFromStdinReadsCachedSalesData() throws {
        let workingDirectory = try makeTempDirectory()
        try seedSubscriptionCache(in: workingDirectory)

        let spec = DataQuerySpec(
            dataset: .sales,
            operation: .aggregate,
            time: QueryTimeSelection(datePT: "2026-02-18"),
            filters: QueryFilterSet(sourceReport: ["subscription"])
        )
        let input = try JSONEncoder().encode(spec)
        let result = try runProcess(
            arguments: ["query", "run", "--spec", "-", "--offline", "--output", "json"],
            workingDirectory: workingDirectory,
            stdinData: input
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"dataset\" : \"sales\""))
        XCTAssertTrue(result.output.contains("\"subscribers\""))
    }

    func testSalesAggregateCommandUsesNewDirectQueryShape() throws {
        let workingDirectory = try makeTempDirectory()
        try seedSubscriptionCache(in: workingDirectory)

        let result = try runProcess(
            arguments: ["sales", "aggregate", "--date", "2026-02-18", "--source-report", "subscription", "--offline", "--output", "table"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Active Subscriptions"))
        XCTAssertTrue(result.output.contains("Subscribers"))
    }

    func testBriefDailyRunsOfflineSummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "daily", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Daily Summary\""))
        XCTAssertTrue(result.output.contains("\"period\" : \"daily\""))
        XCTAssertTrue(result.output.contains("\"sections\""))
    }

    func testBriefDailyWarnsWhenCurrentWindowHasNoSourceData() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "daily", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"code\" : \"summary-no-data\""), result.output)
        XCTAssertTrue(result.output.contains("no data loaded"), result.output)
    }

    func testBriefWeeklyRunsWithoutConflictingTimeSelectors() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "weekly", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Week to Date Summary\""))
        XCTAssertTrue(result.output.contains("\"currentLabel\" : \"this week to date"))
        XCTAssertTrue(result.output.contains("\"Overview\""))
    }

    func testBriefMonthlyRunsOfflineSummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "monthly", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Month to Date Summary\""))
        XCTAssertTrue(result.output.contains("\"timeBasis\""))
        XCTAssertTrue(result.output.contains("\"Data Health\""))
    }

    func testBriefLastMonthRunsOfflineSummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "last-month", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Last Month Summary\""))
        XCTAssertTrue(result.output.contains("\"period\" : \"last-month\""))
    }

    func testBriefLastMonthKeepsLatestSubscriptionSnapshotPerApp() throws {
        let workingDirectory = try makeTempDirectory()
        try seedLastMonthSubscriptionSnapshotCache(in: workingDirectory)
        let currentWindow = PTDateRangePreset.lastMonth.resolve()

        let subscriptionRecords = try runProcess(
            arguments: [
                "sales", "records",
                "--from", currentWindow.startDatePT,
                "--to", currentWindow.endDatePT,
                "--source-report", "subscription",
                "--offline",
                "--output", "json"
            ],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(subscriptionRecords.status, 0, subscriptionRecords.output)
        XCTAssertTrue(subscriptionRecords.output.contains("App A"), subscriptionRecords.output)
        XCTAssertTrue(subscriptionRecords.output.contains("App B"), subscriptionRecords.output)

        let result = try runProcess(
            arguments: ["brief", "last-month", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        let data = try XCTUnwrap(result.output.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sections = try XCTUnwrap(json["sections"] as? [[String: Any]])
        let overview = try XCTUnwrap(sections.first { ($0["title"] as? String) == "Overview" })
        let table = try XCTUnwrap(overview["table"] as? [String: Any])
        let rows = try XCTUnwrap(table["rows"] as? [[String]])
        let activeSubs = try XCTUnwrap(rows.first { $0.first == "Active Subscriptions" })
        XCTAssertEqual(activeSubs[safe: 1], "50")
    }

    func testBriefLastMonthDataHealthReflectsActualSalesCoverage() throws {
        let workingDirectory = try makeTempDirectory()
        try seedLastMonthMonthlySalesCache(in: workingDirectory)

        let result = try runProcess(
            arguments: ["brief", "last-month", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        let data = try XCTUnwrap(result.output.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sections = try XCTUnwrap(json["sections"] as? [[String: Any]])
        let dataHealth = try XCTUnwrap(sections.first { ($0["title"] as? String) == "Data Health" })
        let table = try XCTUnwrap(dataHealth["table"] as? [String: Any])
        let rows = try XCTUnwrap(table["rows"] as? [[String]])
        XCTAssertEqual(rows.first { $0.first == "Sales As Of" }?[safe: 1], "2026-03-01")
        XCTAssertEqual(rows.first { $0.first == "Sales Coverage Days" }?[safe: 1], "1")
    }

    func testBriefLastMonthReviewCoverageUsesCurrentRangeOnly() throws {
        let workingDirectory = try makeTempDirectory()
        try seedLastMonthReviewCoverageCache(in: workingDirectory)

        let result = try runProcess(
            arguments: ["brief", "last-month", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        let data = try XCTUnwrap(result.output.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sections = try XCTUnwrap(json["sections"] as? [[String: Any]])
        let dataHealth = try XCTUnwrap(sections.first { ($0["title"] as? String) == "Data Health" })
        let table = try XCTUnwrap(dataHealth["table"] as? [String: Any])
        let rows = try XCTUnwrap(table["rows"] as? [[String]])
        XCTAssertEqual(rows.first { $0.first == "Review Coverage Days" }?[safe: 1], "1")
    }

    func testOverviewAliasRunsDailySummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["overview", "daily", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"period\" : \"daily\""))
        XCTAssertTrue(result.output.contains("\"title\" : \"Daily Summary\""))
    }

    func testQueryRunBriefUsesBriefSummaryShape() throws {
        let workingDirectory = try makeTempDirectory()

        let spec = DataQuerySpec(
            dataset: .brief,
            operation: .brief,
            time: QueryTimeSelection(rangePreset: "this-week")
        )
        let input = try JSONEncoder().encode(spec)
        let result = try runProcess(
            arguments: ["query", "run", "--spec", "-", "--offline", "--output", "json"],
            workingDirectory: workingDirectory,
            stdinData: input
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"period\" : \"weekly\""))
        XCTAssertTrue(result.output.contains("\"sections\""))
        XCTAssertTrue(result.output.contains("\"timeBasis\""))
    }

    func testConfigCurrencySetWritesLocalReportingCurrency() throws {
        let workingDirectory = try makeTempDirectory()

        let setResult = try runProcess(
            arguments: ["config", "currency", "set", "CNY", "--local", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(setResult.status, 0, setResult.output)
        XCTAssertTrue(setResult.output.contains("\"reportingCurrency\" : \"CNY\""))

        let showResult = try runProcess(
            arguments: ["config", "currency", "show", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(showResult.status, 0, showResult.output)
        XCTAssertTrue(showResult.output.contains("\"reportingCurrency\" : \"CNY\""))
    }

    func testConfigTimezoneSetWritesLocalDisplayTimezone() throws {
        let workingDirectory = try makeTempDirectory()

        let setResult = try runProcess(
            arguments: ["config", "timezone", "set", "America/Los_Angeles", "--local", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(setResult.status, 0, setResult.output)
        XCTAssertTrue(setResult.output.contains("\"displayTimeZone\" : \"America\\/Los_Angeles\""))

        let showResult = try runProcess(
            arguments: ["config", "timezone", "show", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(showResult.status, 0, showResult.output)
        XCTAssertTrue(showResult.output.contains("\"displayTimeZone\" : \"America\\/Los_Angeles\""))
    }

    func testSalesAggregateRejectsUnknownSourceReport() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["sales", "aggregate", "--date", "2026-02-18", "--source-report", "not-a-report", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Unsupported sales source-report"))
        XCTAssertTrue(result.output.contains("summary-sales"))
    }

    func testSalesHelpMentionsSourceReportSpecificLimits() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["sales", "aggregate", "--help"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Not every sales source-report supports every filter or group-by"), result.output)
        XCTAssertTrue(result.output.contains("subscription-event"), result.output)
    }

    func testAnalyticsHelpMentionsEngagementVersionLimit() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["analytics", "aggregate", "--help"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("engagement does not support --app-version or group-by version"), result.output)
    }

    func testCapabilitiesOutputMentionsSourceReportSpecificLimits() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["capabilities", "list", "--output", "markdown"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("subscription-event"), result.output)
        XCTAssertTrue(result.output.contains("engagement does not support app-version filter or version group-by"), result.output)
        XCTAssertTrue(result.output.contains("app-version"), result.output)
    }

    func testQuerySpecDocumentsSourceReportSpecificLimits() throws {
        let content = try repoFile("docs/query-spec.md")

        XCTAssertTrue(content.contains("summary-sales`, `pre-order`, `subscription-offer-redemption` only"))
        XCTAssertTrue(content.contains("`acquisition`, `usage`, `performance` only"))
    }

    func testSalesAggregateDoesNotAcceptCompareOptions() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["sales", "aggregate", "--range", "last-7d", "--compare", "previous-period", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Unknown option '--compare'"), result.output)
    }

    func testSalesAggregateRejectsUnsupportedRatingFilter() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["sales", "aggregate", "--range", "last-7d", "--group-by", "territory", "--rating", "5", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Unknown option '--rating'"), result.output)
    }

    func testSalesAggregateRejectsFiscalMonthOption() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["sales", "aggregate", "--fiscal-month", "2026-02", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Unknown option '--fiscal-month'"), result.output)
    }

    func testFinanceAggregateRejectsDateOption() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["finance", "aggregate", "--date", "2026-01-15", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Unknown option '--date'"), result.output)
    }

    private func seedSubscriptionCache(in workingDirectory: URL) throws {
        try writeLocalConfig(in: workingDirectory)
        let root = workingDirectory.appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()

        let text = try fixture(named: "subscription_2026-02-18.tsv")
        let rows = try ReportParser().parseSubscription(
            tsv: text,
            fallbackDatePT: try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-02-18"))
        )
        let fileURL = cacheStore.reportsDirectory.appendingPathComponent("subscription_2026-02-18.tsv")
        try LocalFileSecurity.writePrivateData(Data(text.utf8), to: fileURL)
        _ = try cacheStore.record(
            report: DownloadedReport(
                source: .sales,
                reportType: "SUBSCRIPTION",
                reportSubType: "SUMMARY",
                queryHash: "subscription_2026-02-18",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: fileURL,
                rawText: text
            )
        )
        try writeFXRates(
            cacheStore: cacheStore,
            requests: Set(rows.map { FXSeedRequest(dateKey: $0.businessDatePT.ptDateString, sourceCurrencyCode: $0.proceedsCurrency) })
        )
    }

    private func seedLastMonthSubscriptionSnapshotCache(in workingDirectory: URL) throws {
        try writeLocalConfig(in: workingDirectory)
        let root = workingDirectory.appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()

        let currentWindow = PTDateRangePreset.lastMonth.resolve()
        let previousMonthDate = try XCTUnwrap(Calendar.pacific.date(byAdding: .day, value: -1, to: currentWindow.startDate))
        let previousMonthEnd = try XCTUnwrap(Calendar.pacific.dateInterval(of: .month, for: previousMonthDate)?.end)
        let previousWindowEnd = try XCTUnwrap(Calendar.pacific.date(byAdding: .day, value: -1, to: previousMonthEnd))
        let laggingCurrentDate = try XCTUnwrap(Calendar.pacific.date(byAdding: .day, value: -1, to: currentWindow.endDate))

        try recordSubscriptionSnapshot(
            cacheStore: cacheStore,
            filename: "subscription-current-a.tsv",
            datePT: currentWindow.endDatePT,
            appName: "App A",
            appAppleID: "1001",
            subscriptionName: "Pro Monthly",
            subscriptionAppleID: "sub.a",
            activeSubscriptions: 30,
            subscribers: 30
        )
        try recordSubscriptionSnapshot(
            cacheStore: cacheStore,
            filename: "subscription-current-b.tsv",
            datePT: laggingCurrentDate.ptDateString,
            appName: "App B",
            appAppleID: "1002",
            subscriptionName: "Pro Monthly",
            subscriptionAppleID: "sub.b",
            activeSubscriptions: 20,
            subscribers: 20
        )
        try recordSubscriptionSnapshot(
            cacheStore: cacheStore,
            filename: "subscription-previous.tsv",
            datePT: previousWindowEnd.ptDateString,
            appName: "App A",
            appAppleID: "1001",
            subscriptionName: "Pro Monthly",
            subscriptionAppleID: "sub.a",
            activeSubscriptions: 25,
            subscribers: 25
        )
        try recordSubscriptionSnapshot(
            cacheStore: cacheStore,
            filename: "subscription-previous-b.tsv",
            datePT: previousWindowEnd.ptDateString,
            appName: "App B",
            appAppleID: "1002",
            subscriptionName: "Pro Monthly",
            subscriptionAppleID: "sub.b",
            activeSubscriptions: 10,
            subscribers: 10
        )
    }

    private func recordSubscriptionSnapshot(
        cacheStore: CacheStore,
        filename: String,
        datePT: String,
        appName: String,
        appAppleID: String,
        subscriptionName: String,
        subscriptionAppleID: String,
        activeSubscriptions: Int,
        subscribers: Int
    ) throws {
        let text = """
        Date\tApp Name\tApp Apple ID\tSubscription Name\tSubscription Apple ID\tSubscription Group ID\tStandard Subscription Duration\tDeveloper Proceeds\tProceeds Currency\tCustomer Currency\tDevice\tCountry\tActive Standard Price Subscriptions\tSubscribers
        \(datePT)\t\(appName)\t\(appAppleID)\t\(subscriptionName)\t\(subscriptionAppleID)\tgroup1\t1 Month\t9.99\tUSD\tUSD\tiPhone\tUS\t\(activeSubscriptions)\t\(subscribers)
        """
        let fileURL = cacheStore.reportsDirectory.appendingPathComponent(filename)
        try LocalFileSecurity.writePrivateData(Data(text.utf8), to: fileURL)
        _ = try cacheStore.record(
            report: DownloadedReport(
                source: .sales,
                reportType: "SUBSCRIPTION",
                reportSubType: "SUMMARY",
                queryHash: filename,
                reportDateKey: datePT,
                vendorNumber: "TEST_VENDOR",
                fileURL: fileURL,
                rawText: text
            )
        )
    }

    private func seedLastMonthMonthlySalesCache(in workingDirectory: URL) throws {
        try writeLocalConfig(in: workingDirectory)
        let root = workingDirectory.appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()

        let currentWindow = PTDateRangePreset.lastMonth.resolve()
        let fileURL = cacheStore.reportsDirectory.appendingPathComponent("summary-monthly.tsv")
        let text = """
        Date\tTitle\tParent Identifier\tApple Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCustomer Price\tCustomer Currency\tTerritory\tDevice\tProduct Type Identifier
        \(currentWindow.startDatePT)\tTest App\t123456789\t123456789\t1\t1\tUSD\t1\tUSD\tUS\tiPhone\t1
        """
        try LocalFileSecurity.writePrivateData(Data(text.utf8), to: fileURL)
        _ = try cacheStore.record(
            report: DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY_MONTHLY",
                queryHash: "summary-monthly",
                reportDateKey: currentWindow.endDate.fiscalMonthString,
                vendorNumber: "TEST_VENDOR",
                fileURL: fileURL,
                rawText: text
            )
        )
    }

    private func seedLastMonthReviewCoverageCache(in workingDirectory: URL) throws {
        try writeLocalConfig(in: workingDirectory)
        let root = workingDirectory.appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()

        let payload = CachedReviewsPayload(
            fetchedAt: Date(),
            reviews: [
                try makeReview(id: "current", date: "2026-03-31", rating: 5, responded: false),
                try makeReview(id: "previous-1", date: "2026-02-26", rating: 5, responded: false),
                try makeReview(id: "previous-2", date: "2026-02-27", rating: 4, responded: false),
                try makeReview(id: "previous-3", date: "2026-02-28", rating: 3, responded: false)
            ]
        )
        try cacheStore.saveReviews(payload, vendorNumber: "TEST_VENDOR")
    }

    private func writeLocalConfig(in workingDirectory: URL) throws {
        let configURL = workingDirectory
            .appendingPathComponent(".app-connect-data-cli", isDirectory: true)
            .appendingPathComponent("config.json")
        let config = ACDConfig(vendorNumber: "TEST_VENDOR", reportingCurrency: "USD", displayTimeZone: "UTC")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try LocalFileSecurity.writePrivateData(try encoder.encode(config), to: configURL)
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

    private func runProcess(
        arguments: [String],
        workingDirectory: URL,
        stdinData: Data? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("adc")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        if let stdinData {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(stdinData)
            try input.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        process.waitUntilExit()
        let rendered = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, rendered)
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("Missing products directory")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".app-connect-data-cli", isDirectory: true),
            withIntermediateDirectories: true
        )
        return url
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

    private func repoFile(_ relativePath: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: path, encoding: .utf8)
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

    private struct FXSeedRequest: Hashable {
        var dateKey: String
        var sourceCurrencyCode: String
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
