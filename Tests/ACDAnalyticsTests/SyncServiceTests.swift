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

final class SyncServiceTests: XCTestCase {
    func testSyncSalesWindowSkipsDailyDownloadsForFullMonths() async throws {
        let cacheStore = try makeCacheStore()
        let fakeClient = CountingSalesClient()
        let downloader = ReportDownloader(
            client: fakeClient,
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
            client: ASCClient(session: .shared, tokenProvider: { "TEST_TOKEN" }),
            vendorNumber: "TEST_VENDOR"
        )

        let window = PTDateRangePreset.lastMonth.resolve(
            reference: try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-04-10"))
        )
        _ = try await syncService.syncSales(window: window, force: false)

        let queries = await fakeClient.recordedQueries()
        XCTAssertEqual(queries.filter { $0.frequency == "DAILY" }.count, 0)
        XCTAssertEqual(queries.filter { $0.frequency == "MONTHLY" }.count, 1)
        XCTAssertEqual(queries.first?.reportDate, "2026-03")
    }

    func testSyncReviewsNormalizesVendorNumberBeforeSavingScopedCache() async throws {
        let cacheStore = try makeCacheStore()
        let fakeClient = ReviewSyncClient()
        let downloader = ReportDownloader(
            client: fakeClient,
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
            client: fakeClient,
            vendorNumber: " TEST_VENDOR "
        )

        _ = try await syncService.syncReviews(
            maxApps: 1,
            perAppLimit: 1,
            totalLimit: 1,
            query: ASCCustomerReviewQuery(sort: .newest)
        )

        let payload = try cacheStore.loadReviews(vendorNumber: "TEST_VENDOR")
        XCTAssertEqual(payload?.reviews.count, 1)
        XCTAssertEqual(payload?.reviews.first?.appName, "Hive")
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

private actor CountingSalesClient: ASCClientProtocol {
    private var queries: [SalesReportQuery] = []

    func validateToken() async throws {}

    func downloadSalesReport(query: SalesReportQuery) async throws -> Data {
        queries.append(query)
        return Data("ok".utf8)
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

    func recordedQueries() -> [SalesReportQuery] {
        queries
    }
}

private actor ReviewSyncClient: ASCClientProtocol {
    func validateToken() async throws {}

    func downloadSalesReport(query: SalesReportQuery) async throws -> Data {
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
        [
            ASCLatestReview(
                id: "review-1",
                appID: "6502647802",
                appName: "Hive",
                bundleID: "studio.bunny.hive",
                rating: 5,
                title: "Great",
                body: "Works",
                reviewerNickname: "tester",
                territory: "US",
                createdDate: Date(timeIntervalSince1970: 1),
                developerResponse: nil
            )
        ]
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
