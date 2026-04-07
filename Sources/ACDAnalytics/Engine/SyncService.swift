import Foundation
import ACDCore

public struct SyncSummary: Codable, Sendable {
    public var records: [CachedReportRecord]
    public var reviewCount: Int

    public init(records: [CachedReportRecord] = [], reviewCount: Int = 0) {
        self.records = records
        self.reviewCount = reviewCount
    }
}

public final class SyncService {
    private let cacheStore: CacheStore
    private let downloader: ReportDownloader
    private let client: ASCClient

    public init(
        cacheStore: CacheStore,
        downloader: ReportDownloader,
        client: ASCClient
    ) {
        self.cacheStore = cacheStore
        self.downloader = downloader
        self.client = client
    }

    public func syncSales(
        dates: [Date],
        monthlyFiscalMonths: [String],
        force: Bool
    ) async throws -> SyncSummary {
        var records: [CachedReportRecord] = []
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        for date in dates {
            let report = try await downloader.fetchSalesDaily(datePT: date, cachePolicy: policy)
            records.append(try cacheStore.record(report: report))
        }
        for fiscalMonth in monthlyFiscalMonths {
            let report = try await downloader.fetchSalesMonthly(fiscalMonth: fiscalMonth, cachePolicy: policy)
            records.append(try cacheStore.record(report: report))
        }
        return SyncSummary(records: records)
    }

    public func syncSubscriptions(
        dates: [Date],
        force: Bool
    ) async throws -> SyncSummary {
        var records: [CachedReportRecord] = []
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        for date in dates {
            let summary = try await downloader.fetchSubscriptionDaily(datePT: date, cachePolicy: policy)
            let events = try await downloader.fetchSubscriptionEventDaily(datePT: date, cachePolicy: policy)
            let subscribers = try await downloader.fetchSubscriberDaily(datePT: date, cachePolicy: policy)
            records.append(try cacheStore.record(report: summary))
            records.append(try cacheStore.record(report: events))
            records.append(try cacheStore.record(report: subscribers))
        }
        return SyncSummary(records: records)
    }

    public func syncFinance(
        fiscalMonths: [String],
        regionCodes: [String],
        reportTypes: [FinanceReportType],
        force: Bool
    ) async throws -> SyncSummary {
        var records: [CachedReportRecord] = []
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        for fiscalMonth in fiscalMonths {
            for reportType in reportTypes {
                for regionCode in regionCodes {
                    let report = try await downloader.fetchFinanceMonth(
                        fiscalMonth: fiscalMonth,
                        reportType: reportType,
                        regionCode: regionCode,
                        cachePolicy: policy
                    )
                    records.append(try cacheStore.record(report: report))
                }
            }
        }
        return SyncSummary(records: records)
    }

    public func syncReviews(
        maxApps: Int?,
        perAppLimit: Int?,
        totalLimit: Int?,
        query: ASCCustomerReviewQuery
    ) async throws -> SyncSummary {
        let reviews = try await client.fetchLatestCustomerReviews(
            maxApps: maxApps,
            perAppLimit: perAppLimit,
            totalLimit: totalLimit,
            appPageLimit: 200,
            pageLimit: 200,
            query: query
        )
        try cacheStore.saveReviews(CachedReviewsPayload(fetchedAt: Date(), reviews: reviews))
        return SyncSummary(records: [], reviewCount: reviews.count)
    }
}
