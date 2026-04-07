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

    public func syncSales(
        window: PTDateWindow,
        force: Bool
    ) async throws -> SyncSummary {
        try await syncSales(
            dates: ptDates(in: window, excludingFullMonths: true),
            monthlyFiscalMonths: fullFiscalMonthsContained(in: window),
            force: force
        )
    }

    public func syncSalesReports(
        window: PTDateWindow,
        reportFamilies: [SalesReportFamily],
        force: Bool
    ) async throws -> SyncSummary {
        let requested = reportFamilies.isEmpty ? [SalesReportFamily.summarySales] : reportFamilies
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        var records: [CachedReportRecord] = []

        if requested.contains(.summarySales) {
            let summary = try await syncSales(window: window, force: force)
            records.append(contentsOf: summary.records)
        }

        let dates = ptDates(in: window)
        for date in dates {
            if requested.contains(.subscription) {
                let report = try await downloader.fetchSubscriptionDaily(datePT: date, cachePolicy: policy)
                records.append(try cacheStore.record(report: report))
            }
            if requested.contains(.subscriptionEvent) {
                let report = try await downloader.fetchSubscriptionEventDaily(datePT: date, cachePolicy: policy)
                records.append(try cacheStore.record(report: report))
            }
            if requested.contains(.subscriber) {
                let report = try await downloader.fetchSubscriberDaily(datePT: date, cachePolicy: policy)
                records.append(try cacheStore.record(report: report))
            }
            if requested.contains(.preOrder) {
                let report = try await downloader.fetchPreOrderDaily(datePT: date, cachePolicy: policy)
                records.append(try cacheStore.record(report: report))
            }
            if requested.contains(.subscriptionOfferRedemption) {
                let report = try await downloader.fetchSubscriptionOfferCodeRedemptionDaily(datePT: date, cachePolicy: policy)
                records.append(try cacheStore.record(report: report))
            }
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

    public func syncSubscriptions(
        window: PTDateWindow,
        force: Bool
    ) async throws -> SyncSummary {
        try await syncSubscriptions(dates: ptDates(in: window), force: force)
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

    public func syncFinance(
        window: PTDateWindow,
        regionCodes: [String],
        reportTypes: [FinanceReportType],
        force: Bool
    ) async throws -> SyncSummary {
        try await syncFinance(
            fiscalMonths: fiscalMonthsOverlapping(window: window),
            regionCodes: regionCodes,
            reportTypes: reportTypes,
            force: force
        )
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
