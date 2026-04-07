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

public enum AnalyticsEngineError: LocalizedError {
    case invalidQuery(String)
    case unsupportedFilter(String)
    case unsupportedGroupBy(String)

    public var errorDescription: String? {
        switch self {
        case .invalidQuery(let message), .unsupportedFilter(let message), .unsupportedGroupBy(let message):
            return message
        }
    }
}

public final class AnalyticsEngine {
    private let cacheStore: CacheStore
    private let parser: ReportParser
    private let syncService: SyncService?
    private let client: ASCClient?
    private let downloader: ReportDownloader?
    private let fxService: FXRateService
    private let reportingCurrency: String

    public init(
        cacheStore: CacheStore,
        parser: ReportParser = ReportParser(),
        syncService: SyncService? = nil,
        client: ASCClient? = nil,
        downloader: ReportDownloader? = nil,
        fxService: FXRateService? = nil,
        reportingCurrency: String = "USD"
    ) {
        self.cacheStore = cacheStore
        self.parser = parser
        self.syncService = syncService
        self.client = client
        self.downloader = downloader
        self.fxService = fxService ?? FXRateService(cacheURL: cacheStore.fxRatesURL)
        let normalizedReportingCurrency = reportingCurrency.normalizedCurrencyCode
        self.reportingCurrency = normalizedReportingCurrency.isUnknownCurrencyCode ? "USD" : normalizedReportingCurrency
    }

    public func capabilities() -> [CapabilityDescriptor] {
        [
            CapabilityDescriptor(
                name: "sales",
                status: "included",
                whatYouCanQuery: [
                    "Summary Sales daily and monthly coverage",
                    "Subscription, Subscription Event, Subscriber reports",
                    "Pre-Order reports",
                    "Subscription Offer Code Redemption reports"
                ],
                whatYouCannotQuery: [
                    "Non-existent ad hoc Trends SQL queries",
                    "User-level identity or cohort exports",
                    "Win-back eligibility in v1"
                ],
                timeSupport: ["date", "from/to", "range", "year"],
                filterSupport: ["app", "version", "territory", "device", "sku", "subscription", "sourceReport"],
                notes: ["Defaults to summary-sales when sourceReport is omitted."]
            ),
            CapabilityDescriptor(
                name: "reviews",
                status: "included",
                whatYouCanQuery: [
                    "Official customer review records",
                    "Territory, rating, response state aggregation",
                    "Volume, average rating, response-rate comparisons"
                ],
                whatYouCannotQuery: [
                    "Review reply write actions",
                    "User-level profiles",
                    "App version from the review API"
                ],
                timeSupport: ["date", "from/to", "range", "year"],
                filterSupport: ["app", "territory"],
                notes: ["Version filtering is unavailable because Apple does not expose app version on review records."]
            ),
            CapabilityDescriptor(
                name: "finance",
                status: "included",
                whatYouCanQuery: [
                    "FINANCIAL and FINANCE_DETAIL report rows",
                    "Vendor proceeds, units, currencies by fiscal month",
                    "Month-over-month and year-over-year finance comparisons"
                ],
                whatYouCannotQuery: [
                    "Daily finance queries",
                    "Real-time finance data"
                ],
                timeSupport: ["fiscalMonth", "fiscalYear", "last-month", "previous-month"],
                filterSupport: ["app", "territory", "sku", "sourceReport"],
                notes: ["Finance uses Apple fiscal month semantics."]
            ),
            CapabilityDescriptor(
                name: "analytics",
                status: "included",
                whatYouCanQuery: [
                    "App Store Downloads",
                    "App Store Discovery and Engagement",
                    "App Sessions",
                    "App Crashes"
                ],
                whatYouCannotQuery: [
                    "Unsupported Analytics report families",
                    "Free-form UI-only analytics pivots",
                    "Immediate data before the first Apple report instance exists"
                ],
                timeSupport: ["date", "from/to", "range", "year"],
                filterSupport: ["app", "territory", "device", "version", "platform", "sourceReport"],
                notes: [
                    "Only Apple Analytics Reports are used.",
                    "The first query may create an Apple report request and return a waiting warning."
                ]
            )
        ]
    }

    public func execute(
        spec: DataQuerySpec,
        offline: Bool = false,
        refresh: Bool = false
    ) async throws -> QueryResult {
        switch spec.dataset {
        case .sales:
            return try await executeSales(spec: spec, offline: offline, refresh: refresh)
        case .reviews:
            return try await executeReviews(spec: spec, offline: offline, refresh: refresh)
        case .finance:
            return try await executeFinance(spec: spec, offline: offline, refresh: refresh)
        case .analytics:
            return try await executeAnalytics(spec: spec, offline: offline, refresh: refresh)
        case .brief:
            throw AnalyticsEngineError.invalidQuery("Brief summaries are handled by adc brief, adc overview, or adc query run --spec.")
        }
    }

    private func executeSales(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool
    ) async throws -> QueryResult {
        let selection = try resolveSelection(dataset: .sales, time: spec.time, defaultPreset: .last7d)
        let requestedReports = normalizedSalesFamilies(filters: spec.filters)
        if offline == false, let syncService {
            _ = try await syncService.syncSalesReports(window: selection.window, reportFamilies: requestedReports, force: refresh)
        }
        let records = try loadSalesRecords(window: selection.window, filters: spec.filters, requestedReports: requestedReports)
        return try await buildResult(
            dataset: .sales,
            spec: spec,
            selection: selection,
            source: requestedReports.map(\.rawValue),
            records: records,
            allowFXNetwork: offline == false
        )
    }

    private func executeReviews(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool
    ) async throws -> QueryResult {
        if spec.filters.version.isEmpty == false {
            throw AnalyticsEngineError.unsupportedFilter("Reviews do not support version filtering because Apple does not expose review app versions.")
        }
        if offline == false, let syncService {
            let query = ASCCustomerReviewQuery(sort: .newest)
            _ = try await syncService.syncReviews(
                maxApps: nil,
                perAppLimit: nil,
                totalLimit: nil,
                query: query
            )
        }
        let selection = try resolveSelection(dataset: .reviews, time: spec.time, defaultPreset: .last7d)
        let records = try loadReviewRecords(window: selection.window, filters: spec.filters)
        return try await buildResult(
            dataset: .reviews,
            spec: spec,
            selection: selection,
            source: ["customer-reviews"],
            records: records,
            allowFXNetwork: false
        )
    }

    private func executeFinance(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool
    ) async throws -> QueryResult {
        let selection = try resolveSelection(dataset: .finance, time: spec.time, defaultPreset: .lastMonth)
        if offline == false, let syncService {
            _ = try await syncService.syncFinance(
                fiscalMonths: selection.fiscalMonths,
                regionCodes: ["ZZ", "Z1"],
                reportTypes: [.financial, .financeDetail],
                force: refresh
            )
        }
        let records = try loadFinanceRecords(fiscalMonths: selection.fiscalMonths, filters: spec.filters)
        let source = spec.filters.sourceReport.isEmpty ? ["financial", "finance-detail"] : spec.filters.sourceReport
        return try await buildResult(
            dataset: .finance,
            spec: spec,
            selection: selection,
            source: source,
            records: records,
            allowFXNetwork: offline == false
        )
    }

    private func executeAnalytics(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool
    ) async throws -> QueryResult {
        let selection = try resolveSelection(dataset: .analytics, time: spec.time, defaultPreset: .last7d)
        let reportDescriptors = normalizedAnalyticsReports(filters: spec.filters)
        let warnings = try await ensureAnalyticsData(
            selection: selection,
            filters: spec.filters,
            descriptors: reportDescriptors,
            offline: offline,
            refresh: refresh
        )
        let records = try loadAnalyticsRecords(window: selection.window, filters: spec.filters, descriptors: reportDescriptors)
        return try await buildResult(
            dataset: .analytics,
            spec: spec,
            selection: selection,
            source: reportDescriptors.map(\.id),
            records: records,
            baseWarnings: warnings + [
                QueryWarning(
                    code: "analytics-privacy",
                    message: "Analytics reports can omit rows or metric values because Apple applies privacy thresholds and late corrections."
                )
            ],
            allowFXNetwork: false
        )
    }

    private func buildResult(
        dataset: QueryDataset,
        spec: DataQuerySpec,
        selection: ResolvedSelection,
        source: [String],
        records: [QueryRecord],
        baseWarnings: [QueryWarning] = [],
        allowFXNetwork: Bool
    ) async throws -> QueryResult {
        let sortedRecords = records.sorted { lhs, rhs in
            (lhs.dimensions["date"] ?? "") > (rhs.dimensions["date"] ?? "")
        }
        switch spec.operation {
        case .records:
            let current = try await normalizeMonetaryRecords(dataset: dataset, records: sortedRecords, allowNetwork: allowFXNetwork)
            let limited = spec.limit.map { Array(current.records.prefix(max(0, $0))) } ?? current.records
            return QueryResult(
                dataset: dataset,
                operation: .records,
                time: selection.envelope,
                filters: spec.filters,
                source: source,
                data: QueryResultData(records: limited),
                warnings: baseWarnings + current.warnings,
                tableModel: makeRecordsTable(dataset: dataset, records: limited)
            )
        case .aggregate:
            let current = try await normalizeMonetaryRecords(dataset: dataset, records: sortedRecords, allowNetwork: allowFXNetwork)
            let aggregateRows = finalizeAggregateRows(
                dataset: dataset,
                rows: aggregate(records: current.records, groupBy: spec.groupBy, dataset: dataset)
            )
            return QueryResult(
                dataset: dataset,
                operation: .aggregate,
                time: selection.envelope,
                filters: spec.filters,
                source: source,
                data: QueryResultData(aggregates: aggregateRows),
                warnings: baseWarnings + current.warnings,
                tableModel: makeAggregateTable(rows: aggregateRows)
            )
        case .compare:
            let mode = spec.compare ?? .previousPeriod
            let previousSelection = try resolveComparisonSelection(dataset: dataset, current: selection, mode: mode, custom: spec.compareTime)
            let previousRecords = try loadRecordsForComparison(
                dataset: dataset,
                filters: spec.filters,
                selection: previousSelection,
                source: source
            )
            let current = try await normalizeMonetaryRecords(dataset: dataset, records: sortedRecords, allowNetwork: allowFXNetwork)
            let previous = try await normalizeMonetaryRecords(dataset: dataset, records: previousRecords, allowNetwork: allowFXNetwork)
            let currentAggregates = finalizeAggregateRows(
                dataset: dataset,
                rows: aggregate(records: current.records, groupBy: spec.groupBy, dataset: dataset)
            )
            let previousAggregates = finalizeAggregateRows(
                dataset: dataset,
                rows: aggregate(records: previous.records, groupBy: spec.groupBy, dataset: dataset)
            )
            let comparisons = compareAggregateRows(current: currentAggregates, previous: previousAggregates)
            return QueryResult(
                dataset: dataset,
                operation: .compare,
                time: selection.envelope,
                filters: spec.filters,
                source: source,
                data: QueryResultData(comparisons: comparisons),
                comparison: QueryComparisonEnvelope(mode: mode, current: selection.envelope, previous: previousSelection.envelope),
                warnings: baseWarnings + current.warnings + previous.warnings,
                tableModel: makeComparisonTable(rows: comparisons)
            )
        case .brief:
            throw AnalyticsEngineError.invalidQuery("Brief summaries are handled by adc brief, adc overview, or adc query run --spec.")
        }
    }

    private func loadRecordsForComparison(
        dataset: QueryDataset,
        filters: QueryFilterSet,
        selection: ResolvedSelection,
        source: [String]
    ) throws -> [QueryRecord] {
        switch dataset {
        case .sales:
            return try loadSalesRecords(
                window: selection.window,
                filters: filters,
                requestedReports: normalizedSalesFamilies(filters: filters)
            )
        case .reviews:
            return try loadReviewRecords(window: selection.window, filters: filters)
        case .finance:
            return try loadFinanceRecords(fiscalMonths: selection.fiscalMonths, filters: filters)
        case .analytics:
            return try loadAnalyticsRecords(
                window: selection.window,
                filters: filters,
                descriptors: normalizedAnalyticsReports(filters: filters)
            )
        case .brief:
            throw AnalyticsEngineError.invalidQuery("Brief summaries do not load comparison records through AnalyticsEngine.")
        }
    }

    private func normalizedSalesFamilies(filters: QueryFilterSet) -> [SalesReportFamily] {
        let candidates = filters.sourceReport.isEmpty ? [SalesReportFamily.summarySales.rawValue] : filters.sourceReport
        let mapped = candidates.compactMap { value -> SalesReportFamily? in
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
            switch normalized {
            case "summary-sales", "sales", "summary":
                return .summarySales
            case "subscription":
                return .subscription
            case "subscription-event", "sales-events":
                return .subscriptionEvent
            case "subscriber":
                return .subscriber
            case "pre-order", "preorder":
                return .preOrder
            case "subscription-offer-redemption", "offer-redemption":
                return .subscriptionOfferRedemption
            default:
                return nil
            }
        }
        return mapped.isEmpty ? [.summarySales] : Array(Set(mapped)).sorted { $0.rawValue < $1.rawValue }
    }

    private struct AnalyticsReportDescriptor {
        let id: String
        let requestName: String
        let category: ASCAnalyticsCategory?
        let preferredAccessType: ASCAnalyticsAccessType
    }

    private func normalizedAnalyticsReports(filters: QueryFilterSet) -> [AnalyticsReportDescriptor] {
        let defaults = ["acquisition", "engagement", "usage", "performance"]
        let inputs = filters.sourceReport.isEmpty ? defaults : filters.sourceReport
        let mapped = inputs.compactMap { value -> AnalyticsReportDescriptor? in
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
            switch normalized {
            case "acquisition", "app-download", "app-downloads":
                return AnalyticsReportDescriptor(
                    id: "acquisition",
                    requestName: "App Store Downloads",
                    category: .commerce,
                    preferredAccessType: .oneTimeSnapshot
                )
            case "engagement", "app-store-discovery-and-engagement":
                return AnalyticsReportDescriptor(
                    id: "engagement",
                    requestName: "App Store Discovery and Engagement",
                    category: .appStoreEngagement,
                    preferredAccessType: .oneTimeSnapshot
                )
            case "usage", "app-sessions":
                return AnalyticsReportDescriptor(
                    id: "usage",
                    requestName: "App Sessions",
                    category: .appUsage,
                    preferredAccessType: .oneTimeSnapshot
                )
            case "performance", "app-crashes":
                return AnalyticsReportDescriptor(
                    id: "performance",
                    requestName: "App Crashes",
                    category: nil,
                    preferredAccessType: .oneTimeSnapshot
                )
            default:
                return nil
            }
        }
        return mapped.isEmpty ? [] : mapped
    }

    private func ensureAnalyticsData(
        selection: ResolvedSelection,
        filters: QueryFilterSet,
        descriptors: [AnalyticsReportDescriptor],
        offline: Bool,
        refresh: Bool
    ) async throws -> [QueryWarning] {
        guard offline == false, let client, let downloader else { return [] }
        let apps = try await resolveAnalyticsApps(filters: filters, client: client)
        guard apps.isEmpty == false else {
            return [QueryWarning(code: "analytics-no-apps", message: "No App Store Connect apps matched the analytics app filter.")]
        }
        let granularity = preferredAnalyticsGranularity(for: selection)
        let processingDateKeys = analyticsProcessingDates(for: selection.window, granularity: granularity)
        let policy: ReportCachePolicy = refresh ? .reloadIgnoringCache : .useCached
        var warnings: [QueryWarning] = []

        for app in apps {
            let accessType = preferredAnalyticsAccessType(for: selection)
            var requests = try await client.listAnalyticsReportRequests(appID: app.id)
            var request = requests.first {
                $0.accessType == accessType && $0.stoppedDueToInactivity == false
            }
            if request == nil {
                request = try await client.createAnalyticsReportRequest(appID: app.id, accessType: accessType)
                warnings.append(
                    QueryWarning(
                        code: "analytics-request-created",
                        message: "Created an Apple Analytics report request for \(app.name). Wait for Apple to generate the first instance before analytics data becomes available."
                    )
                )
                requests = try await client.listAnalyticsReportRequests(appID: app.id)
                request = requests.first {
                    $0.accessType == accessType && $0.stoppedDueToInactivity == false
                }
            }
            guard let activeRequest = request else { continue }

            for descriptor in descriptors {
                let reports = try await client.listAnalyticsReports(
                    requestID: activeRequest.id,
                    category: descriptor.category,
                    name: descriptor.requestName
                )
                guard let report = reports.first(where: { $0.name == descriptor.requestName }) ?? reports.first else {
                    warnings.append(
                        QueryWarning(
                            code: "analytics-report-missing",
                            message: "Apple has not generated the \(descriptor.requestName) report for \(app.name) yet."
                        )
                    )
                    continue
                }

                for processingDate in processingDateKeys {
                    let instances = try await client.listAnalyticsReportInstances(
                        reportID: report.id,
                        granularity: granularity,
                        processingDate: processingDate
                    )
                    for instance in instances {
                        let segments = try await client.listAnalyticsReportSegments(instanceID: instance.id)
                        if segments.isEmpty {
                            warnings.append(
                                QueryWarning(
                                    code: "analytics-instance-pending",
                                    message: "Analytics report instance \(instance.id) has no downloadable segments yet."
                                )
                            )
                        }
                        for segment in segments {
                            let reportDateKey = processingDate
                            let downloaded = try await downloader.fetchAnalyticsSegment(
                                segment: segment,
                                reportName: report.name,
                                reportDateKey: reportDateKey,
                                cachePolicy: policy
                            )
                            _ = try cacheStore.record(report: downloaded)
                        }
                    }
                }
            }
        }

        return warnings
    }

    private func resolveAnalyticsApps(filters: QueryFilterSet, client: ASCClient) async throws -> [ASCAppSummary] {
        let apps = try await client.listApps(limit: nil)
        guard filters.app.isEmpty == false else { return apps }
        return apps.filter { app in
            matchesAny(app.name, in: filters.app)
                || matchesAny(app.id, in: filters.app)
                || matchesAny(app.bundleID ?? "", in: filters.app)
        }
    }

    private func preferredAnalyticsAccessType(for selection: ResolvedSelection) -> ASCAnalyticsAccessType {
        if selection.kind == .year || selection.kind == .range {
            return .oneTimeSnapshot
        }
        return .ongoing
    }

    private func preferredAnalyticsGranularity(for selection: ResolvedSelection) -> ASCAnalyticsGranularity {
        let days = Calendar.pacific.dateComponents([.day], from: selection.window.startDate, to: selection.window.endDate).day ?? 0
        if days >= 90 || selection.kind == .year {
            return .monthly
        }
        if days >= 21 {
            return .weekly
        }
        return .daily
    }

    private func analyticsProcessingDates(for window: PTDateWindow, granularity: ASCAnalyticsGranularity) -> [String] {
        switch granularity {
        case .daily:
            return ptDates(in: window).map(\.ptDateString)
        case .weekly:
            var dates: [String] = []
            let calendar = Calendar.pacific
            var cursor = calendar.dateInterval(of: .weekOfYear, for: window.startDate)?.start ?? window.startDate
            while cursor <= window.endDate {
                let friday = calendar.date(byAdding: .day, value: 4, to: cursor) ?? cursor
                dates.append(friday.ptDateString)
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
                cursor = next
            }
            return dates
        case .monthly:
            return fiscalMonthsOverlapping(window: window).map { "\($0)-05" }
        }
    }

    private func loadSalesRecords(
        window: PTDateWindow,
        filters: QueryFilterSet,
        requestedReports: [SalesReportFamily]
    ) throws -> [QueryRecord] {
        var records: [QueryRecord] = []
        if requestedReports.contains(.summarySales) {
            let rows = try loadSalesSummaryRows(window: window)
            records.append(contentsOf: rows.compactMap { makeSummarySalesRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscription) {
            let rows = try loadSubscriptionRows(reportType: "SUBSCRIPTION")
            records.append(contentsOf: rows.compactMap { makeSubscriptionRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscriptionEvent) {
            let rows = try loadSubscriptionEventRows()
            records.append(contentsOf: rows.compactMap { makeSubscriptionEventRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscriber) {
            let rows = try loadSubscriberRows()
            records.append(contentsOf: rows.compactMap { makeSubscriberRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.preOrder) {
            let rows = try loadSalesGenericRows(reportType: "PRE_ORDER")
            records.append(contentsOf: rows.compactMap { makeGenericSalesRecord(row: $0, reportType: .preOrder, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscriptionOfferRedemption) {
            let rows = try loadSalesGenericRows(reportType: "SUBSCRIPTION_OFFER_CODE_REDEMPTION")
            records.append(contentsOf: rows.compactMap { makeGenericSalesRecord(row: $0, reportType: .subscriptionOfferRedemption, filters: filters, window: window) })
        }
        return records
    }

    private func loadReviewRecords(window: PTDateWindow, filters: QueryFilterSet) throws -> [QueryRecord] {
        guard let payload = try cacheStore.loadReviews() else { return [] }
        return payload.reviews.compactMap { review in
            let reviewDay = Calendar.pacific.startOfDay(for: review.createdDate)
            guard window.startDate <= reviewDay, reviewDay <= window.endDate else { return nil }
            guard filters.app.isEmpty || matchesAny(review.appName, in: filters.app) || matchesAny(review.appID, in: filters.app) else { return nil }
            guard filters.territory.isEmpty || matchesAny(review.territory ?? "", in: filters.territory) else { return nil }
            let responseState = review.developerResponse == nil ? "unresponded" : "responded"
            return QueryRecord(
                id: review.id,
                dimensions: [
                    "date": review.createdDate.ptDateString,
                    "app": review.appName,
                    "territory": review.territory ?? "",
                    "rating": "\(review.rating)",
                    "responseState": responseState,
                    "reportType": "customer-reviews",
                    "sourceReport": "customer-reviews"
                ],
                metrics: [
                    "count": 1,
                    "rating": Double(review.rating),
                    "repliedCount": review.developerResponse == nil ? 0 : 1,
                    "unresolvedCount": review.developerResponse == nil ? 1 : 0,
                    "lowRatingCount": review.rating <= 2 ? 1 : 0
                ]
            )
        }
    }

    private func loadFinanceRecords(fiscalMonths: [String], filters: QueryFilterSet) throws -> [QueryRecord] {
        let manifest = try cacheStore.loadManifest()
        let requested = normalizedStrings(filters.sourceReport)
        let entries = manifest.filter { record in
            guard record.source == .finance else { return false }
            let month = String(record.reportDateKey.prefix(7))
            guard fiscalMonths.contains(month) else { return false }
            if requested.isEmpty { return true }
            let normalizedType = normalizeReportName(record.reportType)
            return requested.contains(normalizedType)
        }
        return try entries.flatMap { entry in
            let fiscalMonth = String(entry.reportDateKey.prefix(7))
            let rows = try parser.parseFinance(
                tsv: loadFile(entry.filePath),
                fiscalMonth: fiscalMonth,
                regionCode: entry.reportSubType,
                vendorNumber: entry.vendorNumber,
                reportVariant: entry.reportType
            )
            return rows.compactMap { (row: ParsedFinanceRow) -> QueryRecord? in
                guard filters.territory.isEmpty || matchesAny(row.countryOfSale, in: filters.territory) else { return nil }
                guard filters.currency.isEmpty || matchesAny(row.currency, in: filters.currency) else { return nil }
                guard filters.sku.isEmpty || matchesAny(row.productRef, in: filters.sku) else { return nil }
                guard filters.app.isEmpty || matchesAny(row.productRef, in: filters.app) else { return nil }
                return QueryRecord(
                    id: row.lineHash,
                    dimensions: [
                        "date": row.businessDatePT.ptDateString,
                        "fiscalMonth": row.fiscalMonth,
                        "territory": row.countryOfSale,
                        "currency": row.currency,
                        "sku": row.productRef,
                        "reportType": row.reportVariant.lowercased(),
                        "sourceReport": normalizeReportName(row.reportVariant)
                    ],
                    metrics: [
                        "units": row.units,
                        "amount": row.amount,
                        "proceeds": row.amount
                    ]
                )
            }
        }
    }

    private func loadAnalyticsRecords(
        window: PTDateWindow,
        filters: QueryFilterSet,
        descriptors: [AnalyticsReportDescriptor]
    ) throws -> [QueryRecord] {
        let manifest = try cacheStore.loadManifest()
        let allowedReportNames = Set(descriptors.map(\.requestName))
        let entries = manifest.filter { record in
            record.source == .analytics && allowedReportNames.contains(record.reportType)
        }
        return try entries.flatMap { entry in
            try parseAnalyticsRecords(tsv: loadFile(entry.filePath), reportName: entry.reportType)
        }.filter { record in
            guard let rawDate = record.dimensions["date"], let date = PTDate(rawDate).date else { return true }
            let day = Calendar.pacific.startOfDay(for: date)
            guard window.startDate <= day, day <= window.endDate else { return false }
            if filters.app.isEmpty == false,
               matchesAny(record.dimensions["app"] ?? "", in: filters.app) == false,
               matchesAny(record.dimensions["appAppleIdentifier"] ?? "", in: filters.app) == false {
                return false
            }
            if filters.territory.isEmpty == false, matchesAny(record.dimensions["territory"] ?? "", in: filters.territory) == false {
                return false
            }
            if filters.device.isEmpty == false, matchesAny(record.dimensions["device"] ?? "", in: filters.device) == false {
                return false
            }
            if filters.platform.isEmpty == false, matchesAny(record.dimensions["platform"] ?? "", in: filters.platform) == false {
                return false
            }
            if filters.version.isEmpty == false, matchesAny(record.dimensions["version"] ?? "", in: filters.version) == false {
                return false
            }
            return true
        }
    }

    private func parseAnalyticsRecords(tsv: String, reportName: String) throws -> [QueryRecord] {
        let lines = tsv.split(whereSeparator: \.isNewline).map(String.init).filter { $0.isEmpty == false }
        guard let headerLine = lines.first else { return [] }
        let delimiter: Character = headerLine.contains("\t") ? "\t" : ","
        let headers = headerLine.split(separator: delimiter).map { normalizeHeader(String($0)) }
        return lines.dropFirst().compactMap { line in
            let cells = line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
            guard cells.count == headers.count else { return nil }
            var dimensions: [String: String] = [
                "reportType": normalizeReportName(reportName),
                "sourceReport": normalizeReportName(reportName)
            ]
            var metrics: [String: Double] = [:]
            for (header, rawValue) in zip(headers, cells) {
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(trimmed.replacingOccurrences(of: ",", with: "")) {
                    metrics[header] = value
                } else if header == "date", let parsed = parseDate(trimmed) {
                    dimensions["date"] = parsed.ptDateString
                } else if trimmed.isEmpty == false {
                    switch header {
                    case "app name":
                        dimensions["app"] = trimmed
                    case "app apple identifier":
                        dimensions["appAppleIdentifier"] = trimmed
                    case "app version":
                        dimensions["version"] = trimmed
                    case "territory":
                        dimensions["territory"] = trimmed
                    case "device":
                        dimensions["device"] = trimmed
                    case "platform":
                        dimensions["platform"] = trimmed
                    default:
                        dimensions[header] = trimmed
                    }
                }
            }
            guard dimensions["date"] != nil || metrics.isEmpty == false else { return nil }
            return QueryRecord(id: line.sha256Hex, dimensions: dimensions, metrics: metrics)
        }
    }

    private func aggregate(
        records: [QueryRecord],
        groupBy: [QueryGroupBy],
        dataset: QueryDataset
    ) -> [QueryAggregateRow] {
        var grouped: [String: (group: [String: String], metrics: [String: Double])] = [:]
        let groups = groupBy.isEmpty ? [] : groupBy
        for record in records {
            let group = makeGroup(record: record, groupBy: groups)
            let key = normalizedGroupKey(group)
            var current = grouped[key] ?? (group, [:])
            for (metric, value) in record.metrics {
                current.metrics[metric, default: 0] += value
            }
            grouped[key] = current
        }
        if grouped.isEmpty, groups.isEmpty {
            let metrics = records.reduce(into: [String: Double]()) { partial, record in
                for (metric, value) in record.metrics {
                    partial[metric, default: 0] += value
                }
            }
            return [QueryAggregateRow(group: [:], metrics: metrics)]
        }
        return grouped.values.map { QueryAggregateRow(group: $0.group, metrics: $0.metrics) }.sorted {
            normalizedGroupKey($0.group) < normalizedGroupKey($1.group)
        }
    }

    private func finalizeAggregateRows(dataset: QueryDataset, rows: [QueryAggregateRow]) -> [QueryAggregateRow] {
        switch dataset {
        case .reviews:
            return rows.map { row in
                let count = row.metrics["count"] ?? 0
                var metrics = row.metrics
                metrics["averageRating"] = count > 0 ? (row.metrics["rating"] ?? 0) / count : 0
                metrics["repliedRate"] = count > 0 ? (row.metrics["repliedCount"] ?? 0) / count : 0
                metrics["lowRatingRatio"] = count > 0 ? (row.metrics["lowRatingCount"] ?? 0) / count : 0
                return QueryAggregateRow(group: row.group, metrics: metrics)
            }
        default:
            return rows
        }
    }

    private func compareAggregateRows(
        current: [QueryAggregateRow],
        previous: [QueryAggregateRow]
    ) -> [QueryComparisonRow] {
        let currentByKey = Dictionary(uniqueKeysWithValues: current.map { (normalizedGroupKey($0.group), $0) })
        let previousByKey = Dictionary(uniqueKeysWithValues: previous.map { (normalizedGroupKey($0.group), $0) })
        let keys = Set(currentByKey.keys).union(previousByKey.keys).sorted()
        return keys.map { key in
            let currentRow = currentByKey[key] ?? QueryAggregateRow(group: [:], metrics: [:])
            let previousRow = previousByKey[key] ?? QueryAggregateRow(group: currentRow.group, metrics: [:])
            let metricKeys = Set(currentRow.metrics.keys).union(previousRow.metrics.keys).sorted()
            let metrics = Dictionary(uniqueKeysWithValues: metricKeys.map { metric in
                (
                    metric,
                    QueryComparisonValue(
                        current: currentRow.metrics[metric] ?? 0,
                        previous: previousRow.metrics[metric] ?? 0
                    )
                )
            })
            return QueryComparisonRow(group: currentRow.group.isEmpty ? previousRow.group : currentRow.group, metrics: metrics)
        }
    }

    private func makeGroup(record: QueryRecord, groupBy: [QueryGroupBy]) -> [String: String] {
        guard groupBy.isEmpty == false else { return [:] }
        var group: [String: String] = [:]
        let date = record.dimensions["date"].flatMap(PTDate.init)?.date
        for item in groupBy {
            switch item {
            case .day:
                group[item.rawValue] = record.dimensions["date"] ?? ""
            case .week:
                if let date {
                    let week = Calendar.pacific.dateInterval(of: .weekOfYear, for: date)?.start.ptDateString ?? record.dimensions["date"] ?? ""
                    group[item.rawValue] = week
                }
            case .month:
                if let date {
                    group[item.rawValue] = date.fiscalMonthString
                }
            case .fiscalMonth:
                group[item.rawValue] = record.dimensions["fiscalMonth"] ?? date?.fiscalMonthString ?? ""
            case .app:
                group[item.rawValue] = record.dimensions["app"] ?? ""
            case .version:
                group[item.rawValue] = record.dimensions["version"] ?? ""
            case .territory:
                group[item.rawValue] = record.dimensions["territory"] ?? ""
            case .currency:
                group[item.rawValue] = record.dimensions["currency"] ?? ""
            case .device:
                group[item.rawValue] = record.dimensions["device"] ?? ""
            case .sku:
                group[item.rawValue] = record.dimensions["sku"] ?? ""
            case .rating:
                group[item.rawValue] = record.dimensions["rating"] ?? ""
            case .responseState:
                group[item.rawValue] = record.dimensions["responseState"] ?? ""
            case .reportType:
                group[item.rawValue] = record.dimensions["reportType"] ?? ""
            case .platform:
                group[item.rawValue] = record.dimensions["platform"] ?? ""
            case .sourceReport:
                group[item.rawValue] = record.dimensions["sourceReport"] ?? ""
            case .subscription:
                group[item.rawValue] = record.dimensions["subscription"] ?? ""
            }
        }
        return group
    }

    private func makeRecordsTable(dataset: QueryDataset, records: [QueryRecord]) -> TableModel {
        let dimensionKeys = Set(records.flatMap { $0.dimensions.keys }).sorted()
        let metricKeys = Set(records.flatMap { $0.metrics.keys }).sorted()
        let columns = dimensionKeys + metricKeys
        let rows = records.map { record in
            columns.map { key in
                if let value = record.dimensions[key] {
                    return value
                }
                if let value = record.metrics[key] {
                    return formatMetric(value)
                }
                return ""
            }
        }
        return TableModel(title: dataset.rawValue, columns: columns, rows: rows)
    }

    private func makeAggregateTable(rows: [QueryAggregateRow]) -> TableModel {
        let groupKeys = Set(rows.flatMap { $0.group.keys }).sorted()
        let metricKeys = Set(rows.flatMap { $0.metrics.keys }).sorted()
        let columns = groupKeys + metricKeys
        let tableRows = rows.map { row in
            columns.map { key in
                if let value = row.group[key] {
                    return value
                }
                if let value = row.metrics[key] {
                    return formatMetric(value)
                }
                return ""
            }
        }
        return TableModel(columns: columns, rows: tableRows)
    }

    private func makeComparisonTable(rows: [QueryComparisonRow]) -> TableModel {
        let groupKeys = Set(rows.flatMap { $0.group.keys }).sorted()
        let metricKeys = Set(rows.flatMap { $0.metrics.keys }).sorted()
        let columns = groupKeys + metricKeys.flatMap { ["\($0) current", "\($0) previous", "\($0) delta", "\($0) delta%"] }
        let tableRows = rows.map { row in
            var mapped: [String] = []
            mapped.append(contentsOf: groupKeys.map { row.group[$0] ?? "" })
            for metric in metricKeys {
                let value = row.metrics[metric]
                mapped.append(formatMetric(value?.current ?? 0))
                mapped.append(formatMetric(value?.previous ?? 0))
                mapped.append(formatMetric(value?.delta ?? 0))
                mapped.append(value?.deltaPercent.map(formatPercent) ?? "")
            }
            return mapped
        }
        return TableModel(columns: columns, rows: tableRows)
    }

    private struct MonetaryNormalizationResult {
        var records: [QueryRecord]
        var warnings: [QueryWarning]
    }

    private func normalizeMonetaryRecords(
        dataset: QueryDataset,
        records: [QueryRecord],
        allowNetwork: Bool
    ) async throws -> MonetaryNormalizationResult {
        switch dataset {
        case .sales:
            return try await normalizeSalesRecords(records: records, allowNetwork: allowNetwork)
        case .finance:
            return try await normalizeFinanceRecords(records: records, allowNetwork: allowNetwork)
        default:
            return MonetaryNormalizationResult(records: records, warnings: [])
        }
    }

    private func normalizeSalesRecords(
        records: [QueryRecord],
        allowNetwork: Bool
    ) async throws -> MonetaryNormalizationResult {
        let proceedsRequests = fxRequests(records: records, metric: "proceeds", currencyDimension: "currency")
        let salesRequests = fxRequests(records: records, metric: "sales", currencyDimension: "customerCurrency")
        let rates = try await fxService.resolveRates(
            for: proceedsRequests.union(salesRequests),
            targetCurrencyCode: reportingCurrency,
            allowNetwork: allowNetwork
        )

        var sawNonReportingCurrency = false
        var missing: Set<String> = []
        let normalized = records.map { record in
            var metrics = record.metrics
            if let proceeds = metrics["proceeds"] {
                if let converted = normalizeCurrencyMetric(
                    amount: proceeds,
                    dateKey: record.dimensions["date"],
                    currencyCode: record.dimensions["currency"],
                    rates: rates,
                    sawNonReportingCurrency: &sawNonReportingCurrency,
                    missing: &missing
                ) {
                    metrics["proceeds"] = converted
                }
            }
            if let sales = metrics["sales"] {
                if let converted = normalizeCurrencyMetric(
                    amount: sales,
                    dateKey: record.dimensions["date"],
                    currencyCode: record.dimensions["customerCurrency"] ?? record.dimensions["currency"],
                    rates: rates,
                    sawNonReportingCurrency: &sawNonReportingCurrency,
                    missing: &missing
                ) {
                    metrics["sales"] = converted
                }
            }
            return QueryRecord(id: record.id, dimensions: record.dimensions, metrics: metrics)
        }

        return MonetaryNormalizationResult(
            records: normalized,
            warnings: try monetaryWarnings(
                sawNonReportingCurrency: sawNonReportingCurrency,
                missing: missing
            )
        )
    }

    private func normalizeFinanceRecords(
        records: [QueryRecord],
        allowNetwork: Bool
    ) async throws -> MonetaryNormalizationResult {
        let requests = fxRequests(records: records, metric: "amount", currencyDimension: "currency")
            .union(fxRequests(records: records, metric: "proceeds", currencyDimension: "currency"))
        let rates = try await fxService.resolveRates(
            for: requests,
            targetCurrencyCode: reportingCurrency,
            allowNetwork: allowNetwork
        )

        var sawNonReportingCurrency = false
        var missing: Set<String> = []
        let normalized = records.map { record in
            var metrics = record.metrics
            if let amount = metrics["amount"] {
                if let converted = normalizeCurrencyMetric(
                    amount: amount,
                    dateKey: record.dimensions["date"],
                    currencyCode: record.dimensions["currency"],
                    rates: rates,
                    sawNonReportingCurrency: &sawNonReportingCurrency,
                    missing: &missing
                ) {
                    metrics["amount"] = converted
                }
            }
            if let proceeds = metrics["proceeds"] {
                if let converted = normalizeCurrencyMetric(
                    amount: proceeds,
                    dateKey: record.dimensions["date"],
                    currencyCode: record.dimensions["currency"],
                    rates: rates,
                    sawNonReportingCurrency: &sawNonReportingCurrency,
                    missing: &missing
                ) {
                    metrics["proceeds"] = converted
                }
            }
            return QueryRecord(id: record.id, dimensions: record.dimensions, metrics: metrics)
        }

        return MonetaryNormalizationResult(
            records: normalized,
            warnings: try monetaryWarnings(
                sawNonReportingCurrency: sawNonReportingCurrency,
                missing: missing
            )
        )
    }

    private func fxRequests(
        records: [QueryRecord],
        metric: String,
        currencyDimension: String
    ) -> Set<FXLookupRequest> {
        Set(records.compactMap { record in
            guard let amount = record.metrics[metric], amount != 0 else { return nil }
            guard let dateKey = record.dimensions["date"], dateKey.isEmpty == false else { return nil }
            guard let currencyCode = record.dimensions[currencyDimension] ?? record.dimensions["currency"], currencyCode.isEmpty == false else {
                return nil
            }
            let normalized = currencyCode.normalizedCurrencyCode
            guard normalized.isUnknownCurrencyCode == false else { return nil }
            return FXLookupRequest(dateKey: dateKey, currencyCode: normalized)
        })
    }

    private func normalizeCurrencyMetric(
        amount: Double,
        dateKey: String?,
        currencyCode: String?,
        rates: [FXLookupRequest: Double],
        sawNonReportingCurrency: inout Bool,
        missing: inout Set<String>
    ) -> Double? {
        guard let dateKey, dateKey.isEmpty == false else { return nil }
        let normalizedCurrency = (currencyCode ?? "").normalizedCurrencyCode
        if normalizedCurrency == reportingCurrency {
            return amount
        }
        if normalizedCurrency.isUnknownCurrencyCode {
            if amount != 0 {
                missing.insert("\(dateKey)/\(normalizedCurrency)")
            }
            return nil
        }
        sawNonReportingCurrency = true
        if let rate = rates[FXLookupRequest(dateKey: dateKey, currencyCode: normalizedCurrency)] {
            return amount * rate
        }
        if amount != 0 {
            missing.insert("\(dateKey)/\(normalizedCurrency)")
        }
        return nil
    }

    private func monetaryWarnings(
        sawNonReportingCurrency: Bool,
        missing: Set<String>
    ) throws -> [QueryWarning] {
        if missing.isEmpty == false {
            let preview = missing.sorted().prefix(4).joined(separator: ", ")
            throw AnalyticsEngineError.invalidQuery(
                "Missing FX rates for \(reportingCurrency): \(preview). Run without --offline to refresh, or switch reporting currency."
            )
        }

        var warnings: [QueryWarning] = []
        if sawNonReportingCurrency {
            warnings.append(
                QueryWarning(
                    code: "currency-normalized",
                    message: "Monetary metrics are normalized to \(reportingCurrency)."
                )
            )
        }
        return warnings
    }

    private func formatMetric(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private func loadSalesSummaryRows(window: PTDateWindow) throws -> [ParsedSalesRow] {
        let manifest = try cacheStore.loadManifest()
        let salesEntries = manifest.filter { record in
            record.source == .sales && record.reportType == "SALES"
        }
        let monthlyEntries = salesEntries.filter { $0.reportSubType == "SUMMARY_MONTHLY" }
        let dailyEntries = salesEntries.filter { $0.reportSubType != "SUMMARY_MONTHLY" }
        let fullMonths = Set(fullFiscalMonthsContained(in: window))

        var rows: [ParsedSalesRow] = []
        for entry in dailyEntries {
            let parsed = try parser.parseSales(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
            rows.append(contentsOf: parsed.filter { row in
                fullMonths.contains(row.businessDatePT.fiscalMonthString) == false
            })
        }
        for entry in monthlyEntries where fullMonths.contains(entry.reportDateKey) {
            rows.append(contentsOf: try parser.parseSales(
                tsv: loadFile(entry.filePath),
                fallbackDatePT: PTDate("\(entry.reportDateKey)-01").date
            ))
        }
        return rows
    }

    private func loadSalesGenericRows(reportType: String) throws -> [ParsedSalesRow] {
        let manifest = try cacheStore.loadManifest()
        let entries = manifest.filter { $0.source == .sales && $0.reportType == reportType }
        return try entries.flatMap { entry in
            try parser.parseSales(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func loadSubscriptionRows(reportType: String) throws -> [ParsedSubscriptionRow] {
        let manifest = try cacheStore.loadManifest()
        let entries = manifest.filter { $0.source == .sales && $0.reportType == reportType }
        return try entries.flatMap { entry in
            try parser.parseSubscription(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func loadSubscriptionEventRows() throws -> [ParsedSubscriptionEventRow] {
        let manifest = try cacheStore.loadManifest()
        let entries = manifest.filter { $0.source == .sales && $0.reportType == "SUBSCRIPTION_EVENT" }
        return try entries.flatMap { entry in
            try parser.parseSubscriptionEvent(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func loadSubscriberRows() throws -> [ParsedSubscriberDailyRow] {
        let manifest = try cacheStore.loadManifest()
        let entries = manifest.filter { $0.source == .sales && $0.reportType == "SUBSCRIBER" }
        return try entries.flatMap { entry in
            try parser.parseSubscriberDaily(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func makeSummarySalesRecord(row: ParsedSalesRow, filters: QueryFilterSet, window: PTDateWindow) -> QueryRecord? {
        makeGenericSalesRecord(row: row, reportType: .summarySales, filters: filters, window: window)
    }

    private func makeGenericSalesRecord(
        row: ParsedSalesRow,
        reportType: SalesReportFamily,
        filters: QueryFilterSet,
        window: PTDateWindow
    ) -> QueryRecord? {
        let day = Calendar.pacific.startOfDay(for: row.businessDatePT)
        guard window.startDate <= day, day <= window.endDate else { return nil }
        guard filters.territory.isEmpty || matchesAny(row.territory, in: filters.territory) else { return nil }
        guard filters.currency.isEmpty || matchesAny(row.currencyOfProceeds, in: filters.currency) || matchesAny(row.customerCurrency, in: filters.currency) else { return nil }
        guard filters.device.isEmpty || matchesAny(row.device, in: filters.device) else { return nil }
        guard filters.sku.isEmpty || matchesAny(row.sku, in: filters.sku) else { return nil }
        if filters.app.isEmpty == false {
            let candidates = [row.title, row.parentIdentifier, row.appleIdentifier]
            guard candidates.contains(where: { matchesAny($0, in: filters.app) }) else { return nil }
        }
        if filters.version.isEmpty == false, matchesAny(row.version, in: filters.version) == false {
            return nil
        }
        let units = row.units
        let sales = row.customerPrice * row.units
        let proceeds = row.developerProceedsPerUnit * row.units
        return QueryRecord(
            id: row.lineHash,
            dimensions: [
                "date": row.businessDatePT.ptDateString,
                "app": row.parentIdentifier.isEmpty ? row.title : row.parentIdentifier,
                "name": row.title,
                "sku": row.sku,
                "version": row.version,
                "territory": row.territory,
                "currency": row.currencyOfProceeds,
                "customerCurrency": row.customerCurrency,
                "device": row.device,
                "productType": row.productTypeIdentifier,
                "reportType": reportType.rawValue,
                "sourceReport": reportType.rawValue
            ],
            metrics: [
                "units": units,
                "sales": sales,
                "proceeds": proceeds,
                "installs": salesInstallUnits(row),
                "purchases": salesPurchaseUnits(row),
                "refunds": salesUnitsForMetrics(row) < 0 ? abs(salesUnitsForMetrics(row)) : 0,
                "qualifiedConversions": salesQualifiedConversionUnits(row)
            ]
        )
    }

    private func makeSubscriptionRecord(
        row: ParsedSubscriptionRow,
        filters: QueryFilterSet,
        window: PTDateWindow
    ) -> QueryRecord? {
        let day = Calendar.pacific.startOfDay(for: row.businessDatePT)
        guard window.startDate <= day, day <= window.endDate else { return nil }
        guard filters.territory.isEmpty || matchesAny(row.country, in: filters.territory) else { return nil }
        guard filters.currency.isEmpty || matchesAny(row.proceedsCurrency, in: filters.currency) || matchesAny(row.customerCurrency, in: filters.currency) else { return nil }
        guard filters.device.isEmpty || matchesAny(row.device, in: filters.device) else { return nil }
        guard filters.subscription.isEmpty || matchesAny(row.subscriptionName, in: filters.subscription) || matchesAny(row.subscriptionAppleID, in: filters.subscription) else {
            return nil
        }
        if filters.app.isEmpty == false, matchesAny(row.appName, in: filters.app) == false, matchesAny(row.appAppleID, in: filters.app) == false {
            return nil
        }
        return QueryRecord(
            id: row.lineHash,
            dimensions: [
                "date": row.businessDatePT.ptDateString,
                "app": row.appName,
                "sku": row.subscriptionAppleID,
                "subscription": row.subscriptionName,
                "subscriptionDuration": row.standardSubscriptionDuration,
                "territory": row.country,
                "currency": row.proceedsCurrency,
                "customerCurrency": row.customerCurrency,
                "device": row.device,
                "reportType": SalesReportFamily.subscription.rawValue,
                "sourceReport": SalesReportFamily.subscription.rawValue
            ],
            metrics: [
                "units": row.subscribersRaw,
                "proceeds": row.developerProceeds,
                "activeSubscriptions": row.activeStandard + row.activeIntroTrial + row.activeIntroPayUpFront + row.activeIntroPayAsYouGo,
                "billingRetry": row.billingRetry,
                "gracePeriod": row.gracePeriod,
                "subscribers": row.subscribersRaw
            ]
        )
    }

    private func makeSubscriptionEventRecord(
        row: ParsedSubscriptionEventRow,
        filters: QueryFilterSet,
        window: PTDateWindow
    ) -> QueryRecord? {
        let day = Calendar.pacific.startOfDay(for: row.businessDatePT)
        guard window.startDate <= day, day <= window.endDate else { return nil }
        guard filters.territory.isEmpty || matchesAny(row.country, in: filters.territory) else { return nil }
        guard filters.currency.isEmpty || matchesAny(row.proceedsCurrency, in: filters.currency) else { return nil }
        guard filters.device.isEmpty || matchesAny(row.device, in: filters.device) else { return nil }
        guard filters.subscription.isEmpty || matchesAny(row.subscriptionName, in: filters.subscription) else { return nil }
        if filters.app.isEmpty == false, matchesAny(row.appName, in: filters.app) == false {
            return nil
        }
        return QueryRecord(
            id: row.lineHash,
            dimensions: [
                "date": row.businessDatePT.ptDateString,
                "app": row.appName,
                "subscription": row.subscriptionName,
                "sku": row.subscriptionAppleID,
                "subscriptionDuration": row.standardSubscriptionDuration,
                "eventName": row.eventName,
                "territory": row.country,
                "currency": row.proceedsCurrency,
                "device": row.device,
                "reportType": SalesReportFamily.subscriptionEvent.rawValue,
                "sourceReport": SalesReportFamily.subscriptionEvent.rawValue
            ],
            metrics: [
                "units": row.eventCount,
                "proceeds": row.developerProceeds,
                "eventCount": row.eventCount
            ]
        )
    }

    private func makeSubscriberRecord(
        row: ParsedSubscriberDailyRow,
        filters: QueryFilterSet,
        window: PTDateWindow
    ) -> QueryRecord? {
        let day = Calendar.pacific.startOfDay(for: row.businessDatePT)
        guard window.startDate <= day, day <= window.endDate else { return nil }
        guard filters.territory.isEmpty || matchesAny(row.country, in: filters.territory) else { return nil }
        guard filters.currency.isEmpty || matchesAny(row.proceedsCurrency, in: filters.currency) else { return nil }
        guard filters.device.isEmpty || matchesAny(row.device, in: filters.device) else { return nil }
        guard filters.subscription.isEmpty || matchesAny(row.subscriptionName, in: filters.subscription) else { return nil }
        if filters.app.isEmpty == false, matchesAny(row.appName, in: filters.app) == false {
            return nil
        }
        return QueryRecord(
            id: row.lineHash,
            dimensions: [
                "date": row.businessDatePT.ptDateString,
                "app": row.appName,
                "subscription": row.subscriptionName,
                "sku": row.subscriptionAppleID,
                "subscriptionDuration": row.standardSubscriptionDuration,
                "territory": row.country,
                "currency": row.proceedsCurrency,
                "device": row.device,
                "reportType": SalesReportFamily.subscriber.rawValue,
                "sourceReport": SalesReportFamily.subscriber.rawValue
            ],
            metrics: [
                "units": row.subscribers,
                "proceeds": row.developerProceeds,
                "subscribers": row.subscribers,
                "billingRetry": row.billingRetry,
                "gracePeriod": row.gracePeriod
            ]
        )
    }

    private func loadFile(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard (try? LocalFileSecurity.validateOwnerOnlyFile(url)) != nil else {
            return ""
        }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func normalizedGroupKey(_ group: [String: String]) -> String {
        group.keys.sorted().map { "\($0)=\(group[$0] ?? "")" }.joined(separator: "|")
    }

    private func deduplicatedWarnings(_ warnings: [QueryWarning]) -> [QueryWarning] {
        var seen: Set<String> = []
        return warnings.filter { warning in
            seen.insert("\(warning.code)|\(warning.message)").inserted
        }
    }

    private func normalizedStrings(_ values: [String]) -> Set<String> {
        Set(values.map(normalizeReportName))
    }

    private func normalizeReportName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private func normalizeHeader(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = DateFormatter.ptDateFormatter.date(from: value) {
            return date
        }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return nil
    }

    private func matchesAny(_ candidate: String, in filters: [String]) -> Bool {
        let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return filters.contains { filter in
            normalizedCandidate == filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private enum SelectionKind {
        case range
        case year
        case fiscalMonths
    }

    private struct ResolvedSelection {
        let kind: SelectionKind
        let original: QueryTimeSelection
        let window: PTDateWindow
        let fiscalMonths: [String]
        let envelope: QueryTimeEnvelope
        let label: String
    }

    private func resolveSelection(
        dataset: QueryDataset,
        time: QueryTimeSelection,
        defaultPreset: PTDateRangePreset
    ) throws -> ResolvedSelection {
        switch dataset {
        case .finance:
            if let fiscalMonth = time.fiscalMonth {
                let start = PTDate("\(fiscalMonth)-01").date ?? Date()
                let end = DateFormatter.ptDateFormatter.date(from: "\(fiscalMonth)-28") ?? start
                return ResolvedSelection(
                    kind: .fiscalMonths,
                    original: QueryTimeSelection(fiscalMonth: fiscalMonth),
                    window: PTDateWindow(startDate: start, endDate: end),
                    fiscalMonths: [fiscalMonth],
                    envelope: QueryTimeEnvelope(label: fiscalMonth, fiscalMonth: fiscalMonth),
                    label: fiscalMonth
                )
            }
            let fiscalYear = time.fiscalYear ?? time.year
            if let fiscalYear {
                let months = fiscalYearMonths(fiscalYear)
                let start = PTDate("\(months.first ?? "\(fiscalYear)-01")-01").date ?? Date()
                let end = PTDate("\(months.last ?? "\(fiscalYear)-12")-28").date ?? start
                return ResolvedSelection(
                    kind: .fiscalMonths,
                    original: QueryTimeSelection(fiscalYear: fiscalYear),
                    window: PTDateWindow(startDate: start, endDate: end),
                    fiscalMonths: months,
                    envelope: QueryTimeEnvelope(label: "FY\(fiscalYear)", fiscalYear: fiscalYear),
                    label: "FY\(fiscalYear)"
                )
            }
            if let preset = PTDateRangePreset(userInput: time.rangePreset ?? defaultPreset.rawValue),
               [.lastMonth, .previousMonth].contains(preset) {
                let resolved = preset.resolve()
                let month = resolved.startDate.fiscalMonthString
                return ResolvedSelection(
                    kind: .fiscalMonths,
                    original: QueryTimeSelection(fiscalMonth: month),
                    window: resolved,
                    fiscalMonths: [month],
                    envelope: QueryTimeEnvelope(label: month, fiscalMonth: month),
                    label: month
                )
            }
            throw AnalyticsEngineError.invalidQuery("Finance queries only support fiscalMonth, fiscalYear, or last-month style presets.")
        default:
            if let year = time.year {
                let window = calendarYearWindow(year: year)
                return ResolvedSelection(
                    kind: .year,
                    original: QueryTimeSelection(year: year),
                    window: window,
                    fiscalMonths: fiscalMonthsOverlapping(window: window),
                    envelope: QueryTimeEnvelope(label: "\(year)", startDatePT: window.startDatePT, endDatePT: window.endDatePT, year: year),
                    label: "\(year)"
                )
            }
            let window = try resolvePTDateWindow(
                datePT: time.datePT,
                startDatePT: time.startDatePT,
                endDatePT: time.endDatePT,
                rangePreset: time.rangePreset,
                defaultPreset: defaultPreset
            ) ?? defaultPreset.resolve()
            return ResolvedSelection(
                kind: .range,
                original: QueryTimeSelection(
                    startDatePT: window.startDatePT,
                    endDatePT: window.endDatePT
                ),
                window: window,
                fiscalMonths: fiscalMonthsOverlapping(window: window),
                envelope: QueryTimeEnvelope(
                    label: "\(window.startDatePT) to \(window.endDatePT)",
                    datePT: time.datePT,
                    startDatePT: window.startDatePT,
                    endDatePT: window.endDatePT
                ),
                label: "\(window.startDatePT) to \(window.endDatePT)"
            )
        }
    }

    private func resolveComparisonSelection(
        dataset: QueryDataset,
        current: ResolvedSelection,
        mode: QueryCompareMode,
        custom: QueryTimeSelection?
    ) throws -> ResolvedSelection {
        switch dataset {
        case .finance:
            let months = current.fiscalMonths
            guard months.isEmpty == false else {
                throw AnalyticsEngineError.invalidQuery("Finance comparison requires fiscal months.")
            }
            switch mode {
            case .custom:
                guard let custom else { throw AnalyticsEngineError.invalidQuery("Custom comparison requires compareTime.") }
                return try resolveSelection(dataset: .finance, time: custom, defaultPreset: .lastMonth)
            case .yearOverYear:
                let shifted = months.compactMap { shiftFiscalMonth($0, by: -12) }
                let fiscalYear = Int(shifted.first?.prefix(4) ?? "")
                return ResolvedSelection(
                    kind: .fiscalMonths,
                    original: QueryTimeSelection(fiscalYear: fiscalYear),
                    window: current.window,
                    fiscalMonths: shifted,
                    envelope: QueryTimeEnvelope(label: "previous fiscal year", fiscalYear: fiscalYear),
                    label: "previous fiscal year"
                )
            case .monthOverMonth, .previousPeriod, .weekOverWeek:
                let shifted = months.compactMap { shiftFiscalMonth($0, by: -months.count) }
                let label = shifted.count == 1 ? (shifted.first ?? "previous month") : "previous period"
                return ResolvedSelection(
                    kind: .fiscalMonths,
                    original: QueryTimeSelection(fiscalMonth: shifted.first, fiscalYear: shifted.count > 1 ? Int(shifted.first?.prefix(4) ?? "") : nil),
                    window: current.window,
                    fiscalMonths: shifted,
                    envelope: QueryTimeEnvelope(label: label, fiscalMonth: shifted.count == 1 ? shifted.first : nil),
                    label: label
                )
            }
        default:
            switch mode {
            case .custom:
                guard let custom else { throw AnalyticsEngineError.invalidQuery("Custom comparison requires compareTime.") }
                return try resolveSelection(dataset: dataset, time: custom, defaultPreset: .last7d)
            case .previousPeriod:
                let days = max(1, (Calendar.pacific.dateComponents([.day], from: current.window.startDate, to: current.window.endDate).day ?? 0) + 1)
                let end = Calendar.pacific.date(byAdding: .day, value: -1, to: current.window.startDate) ?? current.window.startDate
                let start = Calendar.pacific.date(byAdding: .day, value: -(days - 1), to: end) ?? end
                let window = PTDateWindow(startDate: start, endDate: end)
                return ResolvedSelection(
                    kind: .range,
                    original: QueryTimeSelection(startDatePT: window.startDatePT, endDatePT: window.endDatePT),
                    window: window,
                    fiscalMonths: fiscalMonthsOverlapping(window: window),
                    envelope: QueryTimeEnvelope(label: "\(window.startDatePT) to \(window.endDatePT)", startDatePT: window.startDatePT, endDatePT: window.endDatePT),
                    label: "\(window.startDatePT) to \(window.endDatePT)"
                )
            case .weekOverWeek:
                return try shiftedRangeSelection(current: current, days: -7)
            case .monthOverMonth:
                return try shiftedCalendarSelection(current: current, component: .month, value: -1)
            case .yearOverYear:
                return try shiftedCalendarSelection(current: current, component: .year, value: -1)
            }
        }
    }

    private func shiftedRangeSelection(current: ResolvedSelection, days: Int) throws -> ResolvedSelection {
        let calendar = Calendar.pacific
        guard let start = calendar.date(byAdding: .day, value: days, to: current.window.startDate),
              let end = calendar.date(byAdding: .day, value: days, to: current.window.endDate)
        else {
            throw AnalyticsEngineError.invalidQuery("Unable to resolve comparison range.")
        }
        let window = PTDateWindow(startDate: start, endDate: end)
        return ResolvedSelection(
            kind: .range,
            original: QueryTimeSelection(startDatePT: window.startDatePT, endDatePT: window.endDatePT),
            window: window,
            fiscalMonths: fiscalMonthsOverlapping(window: window),
            envelope: QueryTimeEnvelope(label: "\(window.startDatePT) to \(window.endDatePT)", startDatePT: window.startDatePT, endDatePT: window.endDatePT),
            label: "\(window.startDatePT) to \(window.endDatePT)"
        )
    }

    private func shiftedCalendarSelection(
        current: ResolvedSelection,
        component: Calendar.Component,
        value: Int
    ) throws -> ResolvedSelection {
        let calendar = Calendar.pacific
        guard let start = calendar.date(byAdding: component, value: value, to: current.window.startDate),
              let end = calendar.date(byAdding: component, value: value, to: current.window.endDate)
        else {
            throw AnalyticsEngineError.invalidQuery("Unable to resolve comparison range.")
        }
        let window = PTDateWindow(startDate: start, endDate: end)
        return ResolvedSelection(
            kind: .range,
            original: QueryTimeSelection(startDatePT: window.startDatePT, endDatePT: window.endDatePT),
            window: window,
            fiscalMonths: fiscalMonthsOverlapping(window: window),
            envelope: QueryTimeEnvelope(label: "\(window.startDatePT) to \(window.endDatePT)", startDatePT: window.startDatePT, endDatePT: window.endDatePT),
            label: "\(window.startDatePT) to \(window.endDatePT)"
        )
    }

    private func shiftFiscalMonth(_ month: String, by offset: Int) -> String? {
        guard let date = DateFormatter.fiscalMonthFormatter.date(from: month),
              let shifted = Calendar.pacific.date(byAdding: .month, value: offset, to: date)
        else {
            return nil
        }
        return shifted.fiscalMonthString
    }

    private enum ProductKind {
        case app
        case iap
        case subscription
        case other
    }

    private func classifyProduct(productTypeIdentifier: String, parentIdentifier: String) -> ProductKind {
        let code = productTypeIdentifier.uppercased()
        if ["IA1", "IA1-M", "FI1"].contains(code) {
            return .iap
        }
        if ["IAY", "IAY-M", "IA9", "IA9-M"].contains(code) {
            return .subscription
        }
        if parentIdentifier.isEmpty {
            return .app
        }
        return .other
    }

    private func salesUnitsForMetrics(_ row: ParsedSalesRow) -> Double {
        let kind = classifyProduct(productTypeIdentifier: row.productTypeIdentifier, parentIdentifier: row.parentIdentifier)
        let code = row.productTypeIdentifier.uppercased()
        switch kind {
        case .iap, .subscription:
            return row.units
        case .app:
            return ["3F", "7F"].contains(code) ? 0 : row.units
        case .other:
            return 0
        }
    }

    private func salesInstallUnits(_ row: ParsedSalesRow) -> Double {
        classifyProduct(productTypeIdentifier: row.productTypeIdentifier, parentIdentifier: row.parentIdentifier) == .app ? max(0, salesUnitsForMetrics(row)) : 0
    }

    private func salesPurchaseUnits(_ row: ParsedSalesRow) -> Double {
        let kind = classifyProduct(productTypeIdentifier: row.productTypeIdentifier, parentIdentifier: row.parentIdentifier)
        return (kind == .iap || kind == .subscription) ? row.units : 0
    }

    private func salesQualifiedConversionUnits(_ row: ParsedSalesRow) -> Double {
        let kind = classifyProduct(productTypeIdentifier: row.productTypeIdentifier, parentIdentifier: row.parentIdentifier)
        let purchaseUnits = salesPurchaseUnits(row)
        guard purchaseUnits != 0 else { return 0 }
        switch kind {
        case .subscription:
            return isRenewalPurchase(row) ? 0 : purchaseUnits
        case .iap:
            return isLifetimePurchase(row) ? purchaseUnits : 0
        default:
            return 0
        }
    }

    private enum MembershipTier {
        case lifetime
        case yearly
        case monthly
    }

    private func classifyMembershipTier(title: String, sku: String) -> MembershipTier? {
        let normalizedSKU = sku.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lifeTokens = ["lifetime", "forever", "life", "one-time", "onetime", "buyout", "终身", "永久", "买断"]
        if lifeTokens.contains(where: { normalizedSKU.contains($0) || normalizedTitle.contains($0) }) {
            return .lifetime
        }
        let yearlyTokens = ["annually", "annual", "yearly", "year", "yr", "p1y", "1y", "12m", "年", "年度"]
        if yearlyTokens.contains(where: { normalizedSKU.contains($0) || normalizedTitle.contains($0) }) {
            return .yearly
        }
        let monthlyTokens = ["monthlly", "monthly", "month", "p1m", "1m", "月", "月度"]
        if monthlyTokens.contains(where: { normalizedSKU.contains($0) || normalizedTitle.contains($0) }) {
            return .monthly
        }
        return nil
    }

    private func isLifetimePurchase(_ row: ParsedSalesRow) -> Bool {
        classifyMembershipTier(title: row.title, sku: row.sku) == .lifetime
    }

    private func isRenewalPurchase(_ row: ParsedSalesRow) -> Bool {
        let orderType = row.orderType.lowercased()
        if orderType.contains("renew") { return true }
        let proceedsReason = row.proceedsReason.lowercased()
        return proceedsReason.contains("renew")
    }
}
