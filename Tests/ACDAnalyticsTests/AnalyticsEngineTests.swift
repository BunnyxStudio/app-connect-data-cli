import XCTest
import Foundation
@testable import ACDAnalytics
@testable import ACDCore

final class AnalyticsEngineTests: XCTestCase {
    func testSalesSnapshotAndReviewsSummaryFromCache() async throws {
        let temp = try makeTempDirectory()
        let cacheStore = CacheStore(rootDirectory: temp.appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true))
        try cacheStore.prepare()

        let salesFile = cacheStore.reportsDirectory.appendingPathComponent("sales.tsv")
        try LocalFileSecurity.writePrivateData(Data(sampleSalesTSV.utf8), to: salesFile)
        let salesReport = DownloadedReport(
            source: .sales,
            reportType: "SALES",
            reportSubType: "SUMMARY",
            queryHash: "sales-sample",
            reportDateKey: "2026-02-18",
            vendorNumber: "123",
            fileURL: salesFile,
            rawText: sampleSalesTSV
        )
        _ = try cacheStore.record(report: salesReport)

        let financeFile = cacheStore.reportsDirectory.appendingPathComponent("finance.tsv")
        try LocalFileSecurity.writePrivateData(Data(sampleFinanceTSV.utf8), to: financeFile)
        let financeReport = DownloadedReport(
            source: .finance,
            reportType: "FINANCIAL",
            reportSubType: "ZZ",
            queryHash: "finance-sample",
            reportDateKey: "2026-02-FINANCIAL-ZZ",
            vendorNumber: "123",
            fileURL: financeFile,
            rawText: sampleFinanceTSV
        )
        _ = try cacheStore.record(report: financeReport)

        try cacheStore.saveReviews(
            CachedReviewsPayload(
                fetchedAt: Date(),
                reviews: [
                    ASCLatestReview(
                        id: "r1",
                        appID: "a1",
                        appName: "Hive",
                        bundleID: nil,
                        rating: 5,
                        title: "Great",
                        body: "Works well",
                        reviewerNickname: "A",
                        territory: "US",
                        createdDate: try XCTUnwrap(DateFormatter.ptDateFormatter.date(from: "2026-02-18")),
                        developerResponse: nil
                    )
                ]
            )
        )

        let fx = FXRateService(cacheURL: cacheStore.fxCacheURL)
        let engine = AnalyticsEngine(cacheStore: cacheStore, fxService: fx)

        let snapshot = try await engine.snapshot(
            source: .sales,
            filters: QueryFilters(startDatePT: "2026-02-18", endDatePT: "2026-02-18")
        )
        XCTAssertEqual(snapshot.totalPurchases, 1, accuracy: 0.0001)
        XCTAssertEqual(snapshot.totalInstalls, 3, accuracy: 0.0001)

        let reviewsSummary = try engine.reviewsSummary()
        XCTAssertEqual(reviewsSummary.total, 1)
        XCTAssertEqual(reviewsSummary.averageRating, 5, accuracy: 0.0001)

        let modules = try await engine.modules(filters: QueryFilters(startDatePT: "2026-02-18", endDatePT: "2026-02-18"))
        XCTAssertGreaterThanOrEqual(modules.overview.salesBookingUSD, 0)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var sampleSalesTSV: String {
        """
        Begin Date\tEnd Date\tTitle\tSKU\tParent Identifier\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\tDevice\tApple Identifier\tVersion\tOrder Type\tProceeds Reason\tSupported Platforms\tCustomer Price\tCustomer Currency
        2026-02-18\t2026-02-18\tHive App\thive.app\t\t1F\t3\t0\tUSD\tUS\tiPhone\t123\t1.0\t\t\tios\t0\tUSD
        2026-02-18\t2026-02-18\tPro Monthly\tpro.monthly\thive.app\tIAY\t1\t9.99\tUSD\tUS\tiPhone\t124\t1.0\t\t\tios\t9.99\tUSD
        """
    }

    private var sampleFinanceTSV: String {
        """
        Start Date\tEnd Date\tSKU\tCountry of Sale\tPartner Share\tExtended Partner Share\tUnits\tCurrency of Proceeds\tApple Identifier
        2026-02-01\t2026-02-28\tpro.monthly\tUS\t9.99\t9.99\t1\tUSD\t124
        """
    }
}
