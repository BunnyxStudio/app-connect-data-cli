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
@testable import ACDCLI
@testable import ACDAnalytics
@testable import ACDCore

final class BriefSummaryBuilderTests: XCTestCase {
    func testDailyBriefContinuesWhenOptionalSubscriptionSyncFails() async throws {
        let cacheStore = try makeCacheStore()
        let client = BriefSummarySyncClient()
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
        let syncService = SyncService(
            cacheStore: cacheStore,
            downloader: downloader,
            client: client,
            vendorNumber: "TEST_VENDOR"
        )
        let runtime = RuntimeContext(
            config: ACDConfig(vendorNumber: "TEST_VENDOR", reportingCurrency: "USD", displayTimeZone: "UTC"),
            credentials: nil,
            paths: RuntimePaths(
                workingDirectory: cacheStore.rootDirectory,
                localBase: cacheStore.rootDirectory,
                userBase: cacheStore.rootDirectory,
                activeBase: cacheStore.rootDirectory,
                cacheRoot: cacheStore.rootDirectory
            ),
            cacheStore: cacheStore,
            client: nil,
            downloader: nil,
            syncService: syncService,
            analytics: AnalyticsEngine(
                cacheStore: cacheStore,
                vendorNumber: "TEST_VENDOR",
                reportingCurrency: "USD"
            )
        )

        let report = try await BriefSummaryBuilder(runtime: runtime, offline: false, refresh: false).build(period: .daily)

        XCTAssertEqual(report.title, "Daily Summary")
        XCTAssertFalse(report.sections.isEmpty)
        XCTAssertTrue(report.sections.contains { $0.title == "Overview" })
        XCTAssertTrue(report.warnings.isEmpty)
    }

    private func makeCacheStore() throws -> CacheStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()
        return cacheStore
    }
}

private actor BriefSummarySyncClient: ASCClientProtocol {
    func validateToken() async throws {}

    func downloadSalesReport(query: SalesReportQuery) async throws -> Data {
        if query.reportType == "SALES" {
            let reportDate = query.reportDate ?? "2026-01-01"
            return Data(
                """
                Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
                \(reportDate)\t\(reportDate)\tHive\thive.app\t123456789\t1F\t1\t5\tUSD\tUS\tiPhone\t123456789\t1.0\t\t\tios\t5\tUSD
                """.utf8
            )
        }
        if query.reportType == "SUBSCRIPTION" || query.reportType == "SUBSCRIPTION_EVENT" {
            throw URLError(.cannotFindHost)
        }
        throw URLError(.unsupportedURL)
    }

    func downloadFinanceReport(query: FinanceReportQuery) async throws -> Data {
        throw URLError(.unsupportedURL)
    }

    func listApps(limit: Int?) async throws -> [ASCAppSummary] {
        []
    }

    func fetchLatestCustomerReviews(
        maxApps: Int?,
        perAppLimit: Int?,
        totalLimit: Int?,
        appPageLimit: Int,
        pageLimit: Int,
        query: ASCCustomerReviewQuery
    ) async throws -> [ASCLatestReview] {
        []
    }

    func listAnalyticsReportRequests(appID: String) async throws -> [ASCAnalyticsReportRequest] {
        []
    }

    func createAnalyticsReportRequest(
        appID: String,
        accessType: ASCAnalyticsAccessType
    ) async throws -> ASCAnalyticsReportRequest {
        throw URLError(.unsupportedURL)
    }

    func listAnalyticsReports(
        requestID: String,
        category: ASCAnalyticsCategory?,
        name: String?
    ) async throws -> [ASCAnalyticsReport] {
        []
    }

    func listAnalyticsReportInstances(
        reportID: String,
        granularity: ASCAnalyticsGranularity?,
        processingDate: String?
    ) async throws -> [ASCAnalyticsReportInstance] {
        []
    }

    func listAnalyticsReportSegments(instanceID: String) async throws -> [ASCAnalyticsReportSegment] {
        []
    }

    func download(url: URL) async throws -> Data {
        throw URLError(.unsupportedURL)
    }
}
