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
    public var warnings: [QueryWarning]

    public init(records: [CachedReportRecord] = [], reviewCount: Int = 0, warnings: [QueryWarning] = []) {
        self.records = records
        self.reviewCount = reviewCount
        self.warnings = warnings
    }
}

public final class SyncService {
    private struct AvailableReportsLoadResult {
        var reports: [DownloadedReport]
        var unavailableCount: Int
    }

    private let maxConcurrentFetches = 3
    private let cacheStore: CacheStore
    private let downloader: ReportDownloader
    private let client: ASCClientProtocol
    private let vendorNumber: String?

    public init(
        cacheStore: CacheStore,
        downloader: ReportDownloader,
        client: ASCClientProtocol,
        vendorNumber: String? = nil
    ) {
        self.cacheStore = cacheStore
        self.downloader = downloader
        self.client = client
        let normalizedVendorNumber = vendorNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vendorNumber = normalizedVendorNumber?.isEmpty == false ? normalizedVendorNumber : nil
    }

    public func syncSales(
        dates: [Date],
        monthlyFiscalMonths: [String],
        force: Bool
    ) async throws -> SyncSummary {
        let downloader = self.downloader
        let policy: ReportCachePolicy = .reloadIgnoringCache
        var operations: [@Sendable () async throws -> DownloadedReport] = []
        operations.reserveCapacity(dates.count + monthlyFiscalMonths.count)

        for date in dates {
            operations.append {
                try await downloader.fetchSalesDaily(datePT: date, cachePolicy: policy)
            }
        }
        for fiscalMonth in monthlyFiscalMonths {
            operations.append {
                try await downloader.fetchSalesMonthly(fiscalMonth: fiscalMonth, cachePolicy: policy)
            }
        }

        let loaded = try await loadAvailableReports(operations)
        let records = try cacheStore.record(reports: loaded.reports)
        return SyncSummary(
            records: records,
            warnings: salesReportNotReadyWarnings(unavailableCount: loaded.unavailableCount)
        )
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
        let downloader = self.downloader
        let policy: ReportCachePolicy = .reloadIgnoringCache
        var records: [CachedReportRecord] = []
        var warnings: [QueryWarning] = []

        if requested.contains(.summarySales) {
            let summary = try await syncSales(window: window, force: force)
            records.append(contentsOf: summary.records)
            warnings.append(contentsOf: summary.warnings)
        }

        let dates = ptDates(in: window)
        var operations: [@Sendable () async throws -> DownloadedReport] = []
        operations.reserveCapacity(dates.count * requested.count)
        for date in dates {
            if requested.contains(.subscription) {
                operations.append {
                    try await downloader.fetchSubscriptionDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.subscriptionEvent) {
                operations.append {
                    try await downloader.fetchSubscriptionEventDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.subscriber) {
                operations.append {
                    try await downloader.fetchSubscriberDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.preOrder) {
                operations.append {
                    try await downloader.fetchPreOrderDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.subscriptionOfferRedemption) {
                operations.append {
                    try await downloader.fetchSubscriptionOfferCodeRedemptionDaily(datePT: date, cachePolicy: policy)
                }
            }
        }

        let loaded = try await loadAvailableReports(operations)
        records.append(contentsOf: try cacheStore.record(reports: loaded.reports))
        warnings.append(contentsOf: salesReportNotReadyWarnings(unavailableCount: loaded.unavailableCount))
        return SyncSummary(records: records, warnings: deduplicatedWarnings(warnings))
    }

    public func syncSubscriptions(
        dates: [Date],
        force: Bool
    ) async throws -> SyncSummary {
        let downloader = self.downloader
        let policy: ReportCachePolicy = .reloadIgnoringCache
        var operations: [@Sendable () async throws -> DownloadedReport] = []
        operations.reserveCapacity(dates.count * 3)
        for date in dates {
            operations.append {
                try await downloader.fetchSubscriptionDaily(datePT: date, cachePolicy: policy)
            }
            operations.append {
                try await downloader.fetchSubscriptionEventDaily(datePT: date, cachePolicy: policy)
            }
            operations.append {
                try await downloader.fetchSubscriberDaily(datePT: date, cachePolicy: policy)
            }
        }

        let loaded = try await loadAvailableReports(operations)
        let records = try cacheStore.record(reports: loaded.reports)
        return SyncSummary(
            records: records,
            warnings: salesReportNotReadyWarnings(unavailableCount: loaded.unavailableCount)
        )
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
        let downloader = self.downloader
        let policy: ReportCachePolicy = .reloadIgnoringCache
        var operations: [@Sendable () async throws -> DownloadedReport] = []
        operations.reserveCapacity(fiscalMonths.count * regionCodes.count * reportTypes.count)
        for fiscalMonth in fiscalMonths {
            for reportType in reportTypes {
                for regionCode in regionCodes {
                    operations.append {
                        try await downloader.fetchFinanceMonth(
                            fiscalMonth: fiscalMonth,
                            reportType: reportType,
                            regionCode: regionCode,
                            cachePolicy: policy
                        )
                    }
                }
            }
        }

        let loaded = try await loadAvailableReports(operations)
        let records = try cacheStore.record(reports: loaded.reports)
        return SyncSummary(
            records: records,
            warnings: financeReportNotReadyWarnings(unavailableCount: loaded.unavailableCount)
        )
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
        try cacheStore.saveReviews(CachedReviewsPayload(fetchedAt: Date(), reviews: reviews), vendorNumber: vendorNumber)
        return SyncSummary(records: [], reviewCount: reviews.count)
    }

    private func loadAvailableReports(
        _ operations: [@Sendable () async throws -> DownloadedReport]
    ) async throws -> AvailableReportsLoadResult {
        guard operations.isEmpty == false else {
            return AvailableReportsLoadResult(reports: [], unavailableCount: 0)
        }

        return try await withThrowingTaskGroup(of: LoadAvailableReportResult.self) { group in
            var iterator = operations.makeIterator()
            var reports: [DownloadedReport] = []
            var unavailableCount = 0

            for _ in 0..<min(maxConcurrentFetches, operations.count) {
                guard let operation = iterator.next() else { break }
                group.addTask {
                    try await Self.loadAvailableReport(operation)
                }
            }

            while let result = try await group.next() {
                if let report = result.report {
                    reports.append(report)
                }
                unavailableCount += result.unavailableCount
                if let next = iterator.next() {
                    group.addTask {
                        try await Self.loadAvailableReport(next)
                    }
                }
            }

            return AvailableReportsLoadResult(reports: reports, unavailableCount: unavailableCount)
        }
    }

    private struct LoadAvailableReportResult {
        var report: DownloadedReport?
        var unavailableCount: Int
    }

    private static func loadAvailableReport(
        _ load: @Sendable () async throws -> DownloadedReport
    ) async throws -> LoadAvailableReportResult {
        do {
            return LoadAvailableReportResult(report: try await load(), unavailableCount: 0)
        } catch ASCClientError.reportNotAvailableYet {
            return LoadAvailableReportResult(report: nil, unavailableCount: 1)
        }
    }

    private func salesReportNotReadyWarnings(unavailableCount: Int) -> [QueryWarning] {
        guard unavailableCount > 0 else { return [] }
        return [
            QueryWarning(
                code: "sales-report-not-ready",
                message: "Apple reported that one or more requested Sales and Trends reports are not available yet. Apple may respond with \"The request expected results but none were found - Report is not available yet.\" For daily Sales and Trends reports, Apple Reporter guidance says availability is staggered: Americas by 5 am PT, Japan, Australia, and New Zealand by 5 am JST, and other territories by 5 am CET. Retry later or use --offline if you already have cached data."
            )
        ]
    }

    private func financeReportNotReadyWarnings(unavailableCount: Int) -> [QueryWarning] {
        guard unavailableCount > 0 else { return [] }
        return [
            QueryWarning(
                code: "finance-report-not-ready",
                message: "Apple reported that one or more requested finance reports are not available yet. Retry later or use --offline if you already have cached data."
            )
        ]
    }

    private func deduplicatedWarnings(_ warnings: [QueryWarning]) -> [QueryWarning] {
        var seen: Set<String> = []
        return warnings.filter { warning in
            seen.insert("\(warning.code)|\(warning.message)").inserted
        }
    }
}
