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

public final class AnalyticsEngine: @unchecked Sendable {
    private let cacheStore: CacheStore
    private let parser: ReportParser
    private let syncService: SyncService?
    private let client: ASCClient?
    private let downloader: ReportDownloader?
    private let fxService: FXRateService
    private let vendorNumber: String?
    private let reportingCurrency: String

    public init(
        cacheStore: CacheStore,
        parser: ReportParser = ReportParser(),
        syncService: SyncService? = nil,
        client: ASCClient? = nil,
        downloader: ReportDownloader? = nil,
        fxService: FXRateService? = nil,
        vendorNumber: String? = nil,
        reportingCurrency: String = "USD"
    ) {
        self.cacheStore = cacheStore
        self.parser = parser
        self.syncService = syncService
        self.client = client
        self.downloader = downloader
        self.fxService = fxService ?? FXRateService(cacheURL: cacheStore.fxRatesURL)
        let normalizedVendorNumber = vendorNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.vendorNumber = normalizedVendorNumber?.isEmpty == false ? normalizedVendorNumber : nil
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
                filterSupport: ["app", "version", "territory", "currency", "device", "sku", "subscription", "sourceReport"],
                notes: [
                    "Defaults to summary-sales when source-report is omitted.",
                    "summary-sales, pre-order, and subscription-offer-redemption support app-version filters. subscription, subscription-event, and subscriber support subscription filters instead."
                ]
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
                filterSupport: ["app", "territory", "rating", "responseState", "sourceReport"],
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
                filterSupport: ["territory", "currency", "sku", "sourceReport"],
                notes: ["Finance uses Apple fiscal month semantics. Defaults to financial when source-report is omitted."]
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
                    "The first query may create an Apple report request and return a waiting warning.",
                    "engagement does not support app-version filter or version group-by. acquisition, usage, and performance do."
                ]
            )
        ]
    }

    public func execute(
        spec: DataQuerySpec,
        offline: Bool = false,
        refresh: Bool = false,
        skipSync: Bool = false
    ) async throws -> QueryResult {
        try validateSpec(spec)
        switch spec.dataset {
        case .sales:
            return try await executeSales(spec: spec, offline: offline, refresh: refresh, skipSync: skipSync)
        case .reviews:
            return try await executeReviews(spec: spec, offline: offline, refresh: refresh, skipSync: skipSync)
        case .finance:
            return try await executeFinance(spec: spec, offline: offline, refresh: refresh, skipSync: skipSync)
        case .analytics:
            return try await executeAnalytics(spec: spec, offline: offline, refresh: refresh, skipSync: skipSync)
        case .brief:
            throw AnalyticsEngineError.invalidQuery("Brief summaries are handled by adc brief, adc overview, or adc query run --spec.")
        }
    }

    private func executeSales(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool,
        skipSync: Bool
    ) async throws -> QueryResult {
        let selection = try resolveSelection(dataset: .sales, time: spec.time, defaultPreset: .last7d)
        let requestedReports = try normalizedSalesFamilies(filters: spec.filters)
        var syncWarnings: [QueryWarning] = []
        let freshnessCutoff = offline || skipSync || syncService == nil ? nil : Date().addingTimeInterval(-1)
        if offline == false, skipSync == false, let syncService {
            let summary = try await syncService.syncSalesReports(window: selection.window, reportFamilies: requestedReports, force: refresh)
            syncWarnings = summary.warnings
            if spec.operation == .compare {
                let previousSelection = try resolveComparisonSelection(
                    dataset: .sales,
                    current: selection,
                    mode: spec.compare ?? .previousPeriod,
                    custom: spec.compareTime
                )
                let previousSummary = try await syncService.syncSalesReports(
                    window: previousSelection.window,
                    reportFamilies: requestedReports,
                    force: refresh
                )
                syncWarnings.append(contentsOf: previousSummary.warnings)
            }
        }
        let records = try loadSalesRecords(
            window: selection.window,
            filters: spec.filters,
            requestedReports: requestedReports,
            freshnessCutoff: freshnessCutoff
        )
        return try await buildResult(
            dataset: .sales,
            spec: spec,
            selection: selection,
            source: requestedReports.map(\.rawValue),
            records: records,
            baseWarnings: deduplicatedWarnings(syncWarnings),
            comparisonFreshnessCutoff: freshnessCutoff,
            allowFXNetwork: offline == false
        )
    }

    private func executeReviews(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool,
        skipSync: Bool
    ) async throws -> QueryResult {
        try validateReviewSourceReports(spec.filters.sourceReport)
        if offline == false, skipSync == false, let syncService {
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
        refresh: Bool,
        skipSync: Bool
    ) async throws -> QueryResult {
        let selection = try resolveSelection(dataset: .finance, time: spec.time, defaultPreset: .lastMonth)
        let requestedReports = try normalizedFinanceSourceReports(filters: spec.filters)
        var syncWarnings: [QueryWarning] = []
        let freshnessCutoff = offline || skipSync || syncService == nil ? nil : Date().addingTimeInterval(-1)
        if offline == false, skipSync == false, let syncService {
            let summary = try await syncService.syncFinance(
                fiscalMonths: selection.fiscalMonths,
                regionCodes: ["ZZ", "Z1"],
                reportTypes: financeReportTypes(for: requestedReports),
                force: refresh
            )
            syncWarnings = summary.warnings
            if spec.operation == .compare {
                let previousSelection = try resolveComparisonSelection(
                    dataset: .finance,
                    current: selection,
                    mode: spec.compare ?? .previousPeriod,
                    custom: spec.compareTime
                )
                let previousSummary = try await syncService.syncFinance(
                    fiscalMonths: previousSelection.fiscalMonths,
                    regionCodes: ["ZZ", "Z1"],
                    reportTypes: financeReportTypes(for: requestedReports),
                    force: refresh
                )
                syncWarnings.append(contentsOf: previousSummary.warnings)
            }
        }
        let records = try loadFinanceRecords(
            fiscalMonths: selection.fiscalMonths,
            filters: spec.filters,
            freshnessCutoff: freshnessCutoff
        )
        let source = requestedReports.isEmpty ? defaultFinanceSourceReports : requestedReports
        return try await buildResult(
            dataset: .finance,
            spec: spec,
            selection: selection,
            source: source,
            records: records,
            baseWarnings: deduplicatedWarnings(syncWarnings),
            comparisonFreshnessCutoff: freshnessCutoff,
            allowFXNetwork: offline == false
        )
    }

    private func executeAnalytics(
        spec: DataQuerySpec,
        offline: Bool,
        refresh: Bool,
        skipSync: Bool
    ) async throws -> QueryResult {
        let selection = try resolveSelection(dataset: .analytics, time: spec.time, defaultPreset: .last7d)
        let reportDescriptors = try normalizedAnalyticsReports(filters: spec.filters)
        let resolvedApps = try await resolvedAnalyticsApps(filters: spec.filters, offline: offline, skipSync: skipSync)
        let executionFilters = expandedAnalyticsFilters(spec.filters, resolvedApps: resolvedApps)
        var warnings: [QueryWarning] = []
        let freshnessCutoff = offline || skipSync || client == nil || downloader == nil ? nil : Date().addingTimeInterval(-1)
        if skipSync == false {
            warnings.append(contentsOf: try await ensureAnalyticsData(
                selection: selection,
                filters: executionFilters,
                descriptors: reportDescriptors,
                apps: resolvedApps,
                offline: offline,
                refresh: refresh
            ))
            if spec.operation == .compare {
                let previousSelection = try resolveComparisonSelection(
                    dataset: .analytics,
                    current: selection,
                    mode: spec.compare ?? .previousPeriod,
                    custom: spec.compareTime
                )
                warnings.append(contentsOf: try await ensureAnalyticsData(
                    selection: previousSelection,
                    filters: executionFilters,
                    descriptors: reportDescriptors,
                    apps: resolvedApps,
                    offline: offline,
                    refresh: refresh
                ))
            }
        }
        let records = try loadAnalyticsRecords(
            window: selection.window,
            filters: executionFilters,
            descriptors: reportDescriptors,
            resolvedApps: resolvedApps,
            freshnessCutoff: freshnessCutoff
        )
        return try await buildResult(
            dataset: .analytics,
            spec: spec,
            selection: selection,
            source: reportDescriptors.map(\.id),
            records: records,
            baseWarnings: deduplicatedWarnings(warnings + [
                QueryWarning(
                    code: "analytics-privacy",
                    message: "Analytics reports can omit rows or metric values because Apple applies privacy thresholds and late corrections."
                )
            ]),
            comparisonFreshnessCutoff: freshnessCutoff,
            executionFilters: executionFilters,
            resolvedAnalyticsApps: resolvedApps,
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
        comparisonFreshnessCutoff: Date? = nil,
        executionFilters: QueryFilterSet? = nil,
        resolvedAnalyticsApps: [ASCAppSummary]? = nil,
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
            let limited = spec.limit.map { Array(aggregateRows.prefix(max(0, $0))) } ?? aggregateRows
            return QueryResult(
                dataset: dataset,
                operation: .aggregate,
                time: selection.envelope,
                filters: spec.filters,
                source: source,
                data: QueryResultData(aggregates: limited),
                warnings: baseWarnings + current.warnings,
                tableModel: makeAggregateTable(dataset: dataset, rows: limited)
            )
        case .compare:
            let mode = spec.compare ?? .previousPeriod
            let previousSelection = try resolveComparisonSelection(dataset: dataset, current: selection, mode: mode, custom: spec.compareTime)
            let previousRecords = try loadRecordsForComparison(
                dataset: dataset,
                filters: executionFilters ?? spec.filters,
                selection: previousSelection,
                source: source,
                resolvedAnalyticsApps: resolvedAnalyticsApps,
                freshnessCutoff: comparisonFreshnessCutoff
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
            let limited = spec.limit.map { Array(comparisons.prefix(max(0, $0))) } ?? comparisons
            return QueryResult(
                dataset: dataset,
                operation: .compare,
                time: selection.envelope,
                filters: spec.filters,
                source: source,
                data: QueryResultData(comparisons: limited),
                comparison: QueryComparisonEnvelope(mode: mode, current: selection.envelope, previous: previousSelection.envelope),
                warnings: baseWarnings + current.warnings + previous.warnings,
                tableModel: makeComparisonTable(dataset: dataset, rows: limited)
            )
        case .brief:
            throw AnalyticsEngineError.invalidQuery("Brief summaries are handled by adc brief, adc overview, or adc query run --spec.")
        }
    }

    private func validateSpec(_ spec: DataQuerySpec) throws {
        try validateCompareCompatibility(spec)
        try validateTimeSelection(dataset: spec.dataset, time: spec.time)
        try validateFilterSupport(dataset: spec.dataset, filters: spec.filters)
        try validateGroupBySupport(spec)
        try validateSalesSourceReportSelection(spec)
        try validateSalesFilterSelection(spec)
        try validateAnalyticsFilterSelection(spec)
        try validateFinanceSourceReportSelection(spec)
    }

    private func validateCompareCompatibility(_ spec: DataQuerySpec) throws {
        switch spec.operation {
        case .compare:
            if spec.compareTime != nil, spec.compare != .custom {
                throw AnalyticsEngineError.invalidQuery("compareTime requires compare=custom.")
            }
        case .records, .aggregate:
            if spec.compare != nil || spec.compareTime != nil {
                throw AnalyticsEngineError.invalidQuery("compare and compareTime are only supported for compare operations.")
            }
        case .brief:
            if spec.dataset != .brief {
                throw AnalyticsEngineError.invalidQuery("brief operation is only supported for the brief dataset.")
            }
        }
    }

    private func validateTimeSelection(dataset: QueryDataset, time: QueryTimeSelection) throws {
        let requested = requestedTimeSelectors(from: time)
        guard requested.isEmpty == false else { return }
        let supported = supportedTimeSelectorSet(for: dataset)
        let unsupported = requested.subtracting(supported)
        guard unsupported.isEmpty == false else { return }

        throw AnalyticsEngineError.invalidQuery(
            "Unsupported \(dataset.rawValue) time selector(s): \(unsupported.sorted().joined(separator: ", ")). Supported selectors: \(supported.sorted().joined(separator: ", "))."
        )
    }

    private func validateFilterSupport(dataset: QueryDataset, filters: QueryFilterSet) throws {
        let supported = supportedFilterSet(for: dataset)
        let unsupported = requestedFilters(from: filters).filter { supported.contains($0) == false }
        if unsupported.isEmpty == false {
            let unsupportedList = displayFilterNames(unsupported).joined(separator: ", ")
            let supportedList = displayFilterNames(supported).joined(separator: ", ")
            throw AnalyticsEngineError.unsupportedFilter(
                "Unsupported \(dataset.rawValue) filter(s): \(unsupportedList). Supported filters: \(supportedList)."
            )
        }

        if dataset == .reviews {
            let invalidRatings = Array(Set(filters.rating.filter { (1...5).contains($0) == false })).sorted()
            if invalidRatings.isEmpty == false {
                let invalidList = invalidRatings.map(String.init).joined(separator: ", ")
                throw AnalyticsEngineError.unsupportedFilter(
                    "Unsupported reviews rating filter: \(invalidList). Supported values: 1, 2, 3, 4, 5."
                )
            }
            if let responseState = nonEmptyString(filters.responseState),
               normalizedReviewResponseState(responseState) == nil {
                throw AnalyticsEngineError.unsupportedFilter(
                    "Unsupported reviews response-state: \(responseState). Supported values: responded, unresponded."
                )
            }
        }
    }

    private func validateGroupBySupport(_ spec: DataQuerySpec) throws {
        guard spec.groupBy.isEmpty == false else { return }

        switch spec.operation {
        case .aggregate, .compare:
            break
        case .records:
            throw AnalyticsEngineError.invalidQuery("groupBy is only supported for aggregate and compare operations.")
        case .brief:
            throw AnalyticsEngineError.invalidQuery("groupBy is not supported for brief queries.")
        }

        let supported = try supportedGroupBySet(for: spec)
        let unsupported = Array(Set(spec.groupBy.filter { supported.contains($0) == false }))
            .sorted { $0.rawValue < $1.rawValue }
        guard unsupported.isEmpty == false else { return }

        let unsupportedList = unsupported.map(\.rawValue).joined(separator: ", ")
        let supportedList = supported.map(\.rawValue).sorted().joined(separator: ", ")
        throw AnalyticsEngineError.unsupportedGroupBy(
            "Unsupported \(spec.dataset.rawValue) group-by value(s): \(unsupportedList). Supported values: \(supportedList)."
        )
    }

    private func validateSalesFilterSelection(_ spec: DataQuerySpec) throws {
        guard spec.dataset == .sales else { return }
        let requested = requestedFilters(from: spec.filters)
        guard requested.isEmpty == false else { return }
        let reports = try normalizedSalesFamilies(filters: spec.filters)
        let supported = reports.reduce(into: Set<String>()) { partial, report in
            let filters = supportedSalesFilterSet(for: report)
            if partial.isEmpty {
                partial = filters
            } else {
                partial.formIntersection(filters)
            }
        }
        let unsupported = requested.filter { supported.contains($0) == false }.sorted()
        guard unsupported.isEmpty == false else { return }
        throw AnalyticsEngineError.unsupportedFilter(
            "Unsupported sales filter(s) for the requested source-report: \(displayFilterNames(unsupported).joined(separator: ", ")). Supported filters: \(displayFilterNames(supported).joined(separator: ", "))."
        )
    }

    private func validateAnalyticsFilterSelection(_ spec: DataQuerySpec) throws {
        guard spec.dataset == .analytics else { return }
        let requested = requestedFilters(from: spec.filters)
        guard requested.isEmpty == false else { return }
        let descriptors = try normalizedAnalyticsReports(filters: spec.filters)
        let supported = descriptors.reduce(into: Set<String>()) { partial, descriptor in
            let filters = supportedAnalyticsFilterSet(for: descriptor)
            if partial.isEmpty {
                partial = filters
            } else {
                partial.formIntersection(filters)
            }
        }
        let unsupported = requested.filter { supported.contains($0) == false }.sorted()
        guard unsupported.isEmpty == false else { return }
        throw AnalyticsEngineError.unsupportedFilter(
            "Unsupported analytics filter(s) for the requested source-report: \(displayFilterNames(unsupported).joined(separator: ", ")). Supported filters: \(displayFilterNames(supported).joined(separator: ", "))."
        )
    }

    private func supportedFilterSet(for dataset: QueryDataset) -> Set<String> {
        switch dataset {
        case .sales:
            return ["app", "version", "territory", "currency", "device", "sku", "subscription", "source-report"]
        case .reviews:
            return ["app", "territory", "rating", "response-state", "source-report"]
        case .finance:
            return ["territory", "currency", "sku", "source-report"]
        case .analytics:
            return ["app", "version", "territory", "device", "platform", "source-report"]
        case .brief:
            return []
        }
    }

    private func supportedGroupBySet(for spec: DataQuerySpec) throws -> Set<QueryGroupBy> {
        switch spec.dataset {
        case .sales:
            let requestedReports = try normalizedSalesFamilies(filters: spec.filters)
            return requestedReports.reduce(into: Set<QueryGroupBy>()) { partial, report in
                let fields = supportedSalesGroupBySet(for: report)
                if partial.isEmpty {
                    partial = fields
                } else {
                    partial.formIntersection(fields)
                }
            }
        case .reviews:
            return [.day, .week, .month, .fiscalMonth, .app, .territory, .rating, .responseState, .reportType, .sourceReport]
        case .finance:
            return [.day, .week, .month, .fiscalMonth, .territory, .currency, .sku, .reportType, .sourceReport]
        case .analytics:
            let descriptors = try normalizedAnalyticsReports(filters: spec.filters)
            return descriptors.reduce(into: Set<QueryGroupBy>()) { partial, descriptor in
                let fields = supportedAnalyticsGroupBySet(for: descriptor)
                if partial.isEmpty {
                    partial = fields
                } else {
                    partial.formIntersection(fields)
                }
            }
        case .brief:
            return []
        }
    }

    private func supportedSalesGroupBySet(for report: SalesReportFamily) -> Set<QueryGroupBy> {
        switch report {
        case .summarySales, .preOrder, .subscriptionOfferRedemption:
            return [.day, .week, .month, .fiscalMonth, .app, .version, .territory, .currency, .device, .sku, .reportType, .sourceReport]
        case .subscription, .subscriptionEvent, .subscriber:
            return [.day, .week, .month, .fiscalMonth, .app, .territory, .currency, .device, .sku, .subscription, .reportType, .sourceReport]
        }
    }

    private func supportedSalesFilterSet(for report: SalesReportFamily) -> Set<String> {
        switch report {
        case .summarySales, .preOrder, .subscriptionOfferRedemption:
            return ["app", "version", "territory", "currency", "device", "sku", "source-report"]
        case .subscription, .subscriptionEvent, .subscriber:
            return ["app", "territory", "currency", "device", "sku", "subscription", "source-report"]
        }
    }

    private func supportedAnalyticsFilterSet(for descriptor: AnalyticsReportDescriptor) -> Set<String> {
        switch descriptor.id {
        case "engagement":
            return ["app", "territory", "device", "platform", "source-report"]
        default:
            return ["app", "version", "territory", "device", "platform", "source-report"]
        }
    }

    private func supportedAnalyticsGroupBySet(for descriptor: AnalyticsReportDescriptor) -> Set<QueryGroupBy> {
        switch descriptor.id {
        case "engagement":
            return [.day, .week, .month, .fiscalMonth, .app, .territory, .device, .platform, .reportType, .sourceReport]
        default:
            return [.day, .week, .month, .fiscalMonth, .app, .version, .territory, .device, .platform, .reportType, .sourceReport]
        }
    }

    private func requestedFilters(from filters: QueryFilterSet) -> Set<String> {
        var names: Set<String> = []
        if filters.app.isEmpty == false { names.insert("app") }
        if filters.version.isEmpty == false { names.insert("version") }
        if filters.territory.isEmpty == false { names.insert("territory") }
        if filters.currency.isEmpty == false { names.insert("currency") }
        if filters.device.isEmpty == false { names.insert("device") }
        if filters.sku.isEmpty == false { names.insert("sku") }
        if filters.subscription.isEmpty == false { names.insert("subscription") }
        if filters.platform.isEmpty == false { names.insert("platform") }
        if filters.sourceReport.isEmpty == false { names.insert("source-report") }
        if filters.rating.isEmpty == false { names.insert("rating") }
        if nonEmptyString(filters.responseState) != nil { names.insert("response-state") }
        return names
    }

    private func displayFilterNames<S: Sequence>(_ names: S) -> [String] where S.Element == String {
        names.map(displayFilterName).sorted()
    }

    private func displayFilterName(_ name: String) -> String {
        switch name {
        case "version":
            return "app-version"
        default:
            return name
        }
    }

    private func requestedTimeSelectors(from time: QueryTimeSelection) -> Set<String> {
        var names: Set<String> = []
        if nonEmptyString(time.datePT) != nil { names.insert("datePT") }
        if nonEmptyString(time.startDatePT) != nil || nonEmptyString(time.endDatePT) != nil {
            names.formUnion(["startDatePT", "endDatePT"])
        }
        if nonEmptyString(time.rangePreset) != nil { names.insert("rangePreset") }
        if time.year != nil { names.insert("year") }
        if nonEmptyString(time.fiscalMonth) != nil { names.insert("fiscalMonth") }
        if time.fiscalYear != nil { names.insert("fiscalYear") }
        return names
    }

    private func supportedTimeSelectorSet(for dataset: QueryDataset) -> Set<String> {
        switch dataset {
        case .sales, .reviews, .analytics:
            return ["datePT", "startDatePT", "endDatePT", "rangePreset", "year"]
        case .finance:
            return ["rangePreset", "fiscalMonth", "fiscalYear", "year"]
        case .brief:
            return ["rangePreset"]
        }
    }

    private func loadRecordsForComparison(
        dataset: QueryDataset,
        filters: QueryFilterSet,
        selection: ResolvedSelection,
        source: [String],
        resolvedAnalyticsApps: [ASCAppSummary]? = nil,
        freshnessCutoff: Date?
    ) throws -> [QueryRecord] {
        switch dataset {
        case .sales:
            return try loadSalesRecords(
                window: selection.window,
                filters: filters,
                requestedReports: try normalizedSalesFamilies(filters: filters),
                freshnessCutoff: freshnessCutoff
            )
        case .reviews:
            try validateReviewSourceReports(filters.sourceReport)
            return try loadReviewRecords(window: selection.window, filters: filters, freshnessCutoff: freshnessCutoff)
        case .finance:
            return try loadFinanceRecords(
                fiscalMonths: selection.fiscalMonths,
                filters: filters,
                freshnessCutoff: freshnessCutoff
            )
        case .analytics:
            return try loadAnalyticsRecords(
                window: selection.window,
                filters: filters,
                descriptors: try normalizedAnalyticsReports(filters: filters),
                resolvedApps: resolvedAnalyticsApps,
                freshnessCutoff: freshnessCutoff
            )
        case .brief:
            throw AnalyticsEngineError.invalidQuery("Brief summaries do not load comparison records through AnalyticsEngine.")
        }
    }

    private func normalizedSalesFamilies(filters: QueryFilterSet) throws -> [SalesReportFamily] {
        let candidates = filters.sourceReport.isEmpty ? [SalesReportFamily.summarySales.rawValue] : filters.sourceReport
        var mapped: [SalesReportFamily] = []
        var invalid: [String] = []
        for value in candidates {
            switch normalizeReportName(value) {
            case "summary-sales", "sales", "summary":
                mapped.append(.summarySales)
            case "subscription":
                mapped.append(.subscription)
            case "subscription-event", "sales-events":
                mapped.append(.subscriptionEvent)
            case "subscriber":
                mapped.append(.subscriber)
            case "pre-order", "preorder":
                mapped.append(.preOrder)
            case "subscription-offer-redemption", "offer-redemption":
                mapped.append(.subscriptionOfferRedemption)
            default:
                invalid.append(value)
            }
        }
        try validateSourceReportInputs(
            invalid,
            dataset: .sales,
            supported: [
                "summary-sales",
                "subscription",
                "subscription-event",
                "subscriber",
                "pre-order",
                "subscription-offer-redemption"
            ]
        )
        return mapped.isEmpty ? [.summarySales] : Array(Set(mapped)).sorted { $0.rawValue < $1.rawValue }
    }

    private struct AnalyticsReportDescriptor {
        let id: String
        let requestName: String
        let category: ASCAnalyticsCategory?
        let preferredAccessType: ASCAnalyticsAccessType
    }

    private func normalizedAnalyticsReports(filters: QueryFilterSet) throws -> [AnalyticsReportDescriptor] {
        let defaults = ["acquisition", "engagement", "usage", "performance"]
        let inputs = filters.sourceReport.isEmpty ? defaults : filters.sourceReport
        var mapped: [AnalyticsReportDescriptor] = []
        var invalid: [String] = []
        for value in inputs {
            switch normalizeReportName(value) {
            case "acquisition", "app-download", "app-downloads":
                mapped.append(
                    AnalyticsReportDescriptor(
                    id: "acquisition",
                    requestName: "App Store Downloads",
                    category: .commerce,
                    preferredAccessType: .oneTimeSnapshot
                )
                )
            case "engagement", "app-store-discovery-and-engagement":
                mapped.append(
                    AnalyticsReportDescriptor(
                    id: "engagement",
                    requestName: "App Store Discovery and Engagement",
                    category: .appStoreEngagement,
                    preferredAccessType: .oneTimeSnapshot
                )
                )
            case "usage", "app-sessions":
                mapped.append(
                    AnalyticsReportDescriptor(
                    id: "usage",
                    requestName: "App Sessions",
                    category: .appUsage,
                    preferredAccessType: .oneTimeSnapshot
                )
                )
            case "performance", "app-crashes":
                mapped.append(
                    AnalyticsReportDescriptor(
                    id: "performance",
                    requestName: "App Crashes",
                    category: nil,
                    preferredAccessType: .oneTimeSnapshot
                )
                )
            default:
                invalid.append(value)
            }
        }
        try validateSourceReportInputs(
            invalid,
            dataset: .analytics,
            supported: ["acquisition", "engagement", "usage", "performance"]
        )
        return mapped.isEmpty ? [] : mapped
    }

    private func validateReviewSourceReports(_ values: [String]) throws {
        guard values.isEmpty == false else { return }
        let invalid = values.filter { value in
            switch normalizeReportName(value) {
            case "customer-reviews", "reviews":
                return false
            default:
                return true
            }
        }
        try validateSourceReportInputs(
            invalid,
            dataset: .reviews,
            supported: ["customer-reviews"]
        )
    }

    private func normalizedFinanceSourceReports(filters: QueryFilterSet) throws -> [String] {
        guard filters.sourceReport.isEmpty == false else { return [] }
        var mapped: [String] = []
        var invalid: [String] = []
        for value in filters.sourceReport {
            switch normalizeReportName(value) {
            case "financial":
                mapped.append("financial")
            case "finance-detail":
                mapped.append("finance-detail")
            default:
                invalid.append(value)
            }
        }
        try validateSourceReportInputs(
            invalid,
            dataset: .finance,
            supported: ["financial", "finance-detail"]
        )
        return Array(Set(mapped)).sorted()
    }

    private var defaultFinanceSourceReports: [String] { ["financial"] }

    func financeReportTypes(for requestedReports: [String]) -> [FinanceReportType] {
        var reportTypes: [FinanceReportType] = []
        if requestedReports.isEmpty || requestedReports.contains("financial") {
            reportTypes.append(.financial)
        }
        if requestedReports.contains("finance-detail") {
            reportTypes.append(.financeDetail)
        }
        return reportTypes
    }

    private func validateFinanceSourceReportSelection(_ spec: DataQuerySpec) throws {
        guard spec.dataset == .finance else { return }
        let requestedReports = try normalizedFinanceSourceReports(filters: spec.filters)
        guard requestedReports.count > 1 else { return }
        guard spec.operation != .records else { return }
        if spec.groupBy.contains(.sourceReport) || spec.groupBy.contains(.reportType) {
            return
        }
        throw AnalyticsEngineError.invalidQuery(
            "Finance aggregate and compare queries cannot combine financial and finance-detail unless grouped by sourceReport or reportType."
        )
    }

    private func validateSalesSourceReportSelection(_ spec: DataQuerySpec) throws {
        guard spec.dataset == .sales else { return }
        let requestedReports = try normalizedSalesFamilies(filters: spec.filters)
        guard requestedReports.count > 1 else { return }
        guard spec.operation != .records else { return }
        if spec.groupBy.contains(.sourceReport) || spec.groupBy.contains(.reportType) {
            return
        }
        throw AnalyticsEngineError.invalidQuery(
            "Sales aggregate and compare queries cannot combine multiple source-report families unless grouped by sourceReport or reportType."
        )
    }

    private func validateSourceReportInputs(
        _ invalid: [String],
        dataset: QueryDataset,
        supported: [String]
    ) throws {
        guard invalid.isEmpty == false else { return }
        let invalidList = invalid.joined(separator: ", ")
        let supportedList = supported.joined(separator: ", ")
        throw AnalyticsEngineError.unsupportedFilter(
            "Unsupported \(dataset.rawValue) source-report: \(invalidList). Supported values: \(supportedList)."
        )
    }

    private func ensureAnalyticsData(
        selection: ResolvedSelection,
        filters: QueryFilterSet,
        descriptors: [AnalyticsReportDescriptor],
        apps: [ASCAppSummary]? = nil,
        offline: Bool,
        refresh: Bool
    ) async throws -> [QueryWarning] {
        guard offline == false, let client, let downloader else { return [] }
        let apps = if let apps {
            apps
        } else {
            try await resolveAnalyticsApps(filters: filters, client: client)
        }
        guard apps.isEmpty == false else {
            return [QueryWarning(code: "analytics-no-apps", message: "No App Store Connect apps matched the analytics app filter.")]
        }
        let granularity = preferredAnalyticsGranularity(for: selection)
        let processingDateKeys = analyticsProcessingDates(for: selection.window, granularity: granularity)
        let policy: ReportCachePolicy = .reloadIgnoringCache
        var warnings: [QueryWarning] = []

        for app in apps {
            let preferredAccessTypes = preferredAnalyticsAccessTypes(for: selection)
            var requests = try await client.listAnalyticsReportRequests(appID: app.id)
            var request = selectAnalyticsRequest(from: requests, preferredAccessTypes: preferredAccessTypes)
            if request == nil {
                request = try await client.createAnalyticsReportRequest(
                    appID: app.id,
                    accessType: preferredAccessTypes.first ?? .ongoing
                )
                warnings.append(
                    QueryWarning(
                        code: "analytics-request-created",
                        message: "Created an Apple Analytics report request for \(app.name). Wait for Apple to generate the first instance before analytics data becomes available."
                    )
                )
                requests = try await client.listAnalyticsReportRequests(appID: app.id)
                request = selectAnalyticsRequest(from: requests, preferredAccessTypes: preferredAccessTypes)
            }
            guard let activeRequest = request else {
                warnings.append(
                    QueryWarning(
                        code: "analytics-request-missing",
                        message: "Apple has not activated a usable Analytics report request for \(app.name) yet."
                    )
                )
                continue
            }

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
                    if instances.isEmpty {
                        warnings.append(
                            QueryWarning(
                                code: "analytics-instance-missing",
                                message: "Apple has not generated the \(descriptor.requestName) \(granularity.rawValue.lowercased()) instance for \(processingDate) for \(app.name) yet."
                            )
                        )
                        continue
                    }
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
                                cacheIdentity: "\(app.id)|\(instance.id)",
                                appID: app.id,
                                bundleID: app.bundleID,
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

    private func resolvedAnalyticsApps(
        filters: QueryFilterSet,
        offline: Bool,
        skipSync: Bool
    ) async throws -> [ASCAppSummary]? {
        guard offline == false, skipSync == false, let client else { return nil }
        return try await resolveAnalyticsApps(filters: filters, client: client)
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

    private func expandedAnalyticsFilters(
        _ filters: QueryFilterSet,
        resolvedApps: [ASCAppSummary]?
    ) -> QueryFilterSet {
        guard filters.app.isEmpty == false, let resolvedApps, resolvedApps.isEmpty == false else {
            return filters
        }
        let expandedApps = Array(
            Set(
                filters.app
                    + resolvedApps.map(\.id)
                    + resolvedApps.compactMap(\.bundleID)
            )
        ).sorted()
        return QueryFilterSet(
            app: expandedApps,
            version: filters.version,
            territory: filters.territory,
            currency: filters.currency,
            device: filters.device,
            sku: filters.sku,
            subscription: filters.subscription,
            platform: filters.platform,
            sourceReport: filters.sourceReport,
            rating: filters.rating,
            responseState: filters.responseState
        )
    }

    private func preferredAnalyticsAccessTypes(for selection: ResolvedSelection) -> [ASCAnalyticsAccessType] {
        if selection.kind == .year {
            return [.oneTimeSnapshot, .ongoing]
        }
        return [.ongoing, .oneTimeSnapshot]
    }

    private func selectAnalyticsRequest(
        from requests: [ASCAnalyticsReportRequest],
        preferredAccessTypes: [ASCAnalyticsAccessType]
    ) -> ASCAnalyticsReportRequest? {
        for accessType in preferredAccessTypes {
            if let request = requests.first(where: {
                $0.accessType == accessType && $0.stoppedDueToInactivity == false
            }) {
                return request
            }
        }
        return nil
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
        requestedReports: [SalesReportFamily],
        freshnessCutoff: Date? = nil
    ) throws -> [QueryRecord] {
        var records: [QueryRecord] = []
        if requestedReports.contains(.summarySales) {
            let rows = try loadSalesSummaryRows(window: window, freshnessCutoff: freshnessCutoff)
            records.append(contentsOf: rows.compactMap { makeSummarySalesRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscription) {
            let rows = try loadSubscriptionRows(window: window, reportType: "SUBSCRIPTION", freshnessCutoff: freshnessCutoff)
            records.append(contentsOf: rows.compactMap { makeSubscriptionRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscriptionEvent) {
            let rows = try loadSubscriptionEventRows(window: window, freshnessCutoff: freshnessCutoff)
            records.append(contentsOf: rows.compactMap { makeSubscriptionEventRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscriber) {
            let rows = try loadSubscriberRows(window: window, freshnessCutoff: freshnessCutoff)
            records.append(contentsOf: rows.compactMap { makeSubscriberRecord(row: $0, filters: filters, window: window) })
        }
        if requestedReports.contains(.preOrder) {
            let rows = try loadSalesGenericRows(window: window, reportType: "PRE_ORDER", freshnessCutoff: freshnessCutoff)
            records.append(contentsOf: rows.compactMap { makeGenericSalesRecord(row: $0, reportType: .preOrder, filters: filters, window: window) })
        }
        if requestedReports.contains(.subscriptionOfferRedemption) {
            let rows = try loadSalesGenericRows(window: window, reportType: "SUBSCRIPTION_OFFER_CODE_REDEMPTION", freshnessCutoff: freshnessCutoff)
            records.append(contentsOf: rows.compactMap { makeGenericSalesRecord(row: $0, reportType: .subscriptionOfferRedemption, filters: filters, window: window) })
        }
        return records
    }

    private func loadReviewRecords(
        window: PTDateWindow,
        filters: QueryFilterSet,
        freshnessCutoff: Date? = nil
    ) throws -> [QueryRecord] {
        guard let payload = try cacheStore.loadReviews(vendorNumber: vendorNumber) else { return [] }
        if let freshnessCutoff, payload.fetchedAt < freshnessCutoff {
            return []
        }
        let allowedRatings = Set(filters.rating)
        let expectedResponseState = normalizedReviewResponseState(filters.responseState)
        return payload.reviews.compactMap { review in
            let reviewDay = Calendar.pacific.startOfDay(for: review.createdDate)
            guard window.startDate <= reviewDay, reviewDay <= window.endDate else { return nil }
            guard filters.app.isEmpty || matchesAny(review.appName, in: filters.app) || matchesAny(review.appID, in: filters.app) else { return nil }
            guard filters.territory.isEmpty || matchesAny(review.territory ?? "", in: filters.territory) else { return nil }
            guard allowedRatings.isEmpty || allowedRatings.contains(review.rating) else { return nil }
            let responseState = review.developerResponse == nil ? "unresponded" : "responded"
            if let expectedResponseState, responseState != expectedResponseState {
                return nil
            }
            return QueryRecord(
                id: review.id,
                dimensions: [
                    "date": review.createdDate.ptDateString,
                    "app": review.appName,
                    "appAppleIdentifier": review.appID,
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

    private func loadFinanceRecords(
        fiscalMonths: [String],
        filters: QueryFilterSet,
        freshnessCutoff: Date? = nil
    ) throws -> [QueryRecord] {
        let requested = normalizedStrings(filters.sourceReport)
        let effectiveRequested = requested.isEmpty ? normalizedStrings(defaultFinanceSourceReports) : requested
        let manifest = try scopedManifestEntries(source: .finance) { record in
            if let freshnessCutoff, record.fetchedAt < freshnessCutoff {
                return false
            }
            let month = String(record.reportDateKey.prefix(7))
            guard fiscalMonths.contains(month) else { return false }
            let normalizedType = normalizeReportName(record.reportType)
            return effectiveRequested.contains(normalizedType)
        }
        let entries = deduplicatedCachedEntries(manifest)
        return try entries.flatMap { entry in
            let fiscalMonth = String(entry.reportDateKey.prefix(7))
            let rows = try parser.parseFinance(
                tsv: try loadFile(entry.filePath),
                fiscalMonth: fiscalMonth,
                regionCode: entry.reportSubType,
                vendorNumber: entry.vendorNumber,
                reportVariant: entry.reportType
            )
            return rows.compactMap { (row: ParsedFinanceRow) -> QueryRecord? in
                guard filters.territory.isEmpty || matchesAny(row.countryOfSale, in: filters.territory) else { return nil }
                guard filters.currency.isEmpty || matchesAny(row.currency, in: filters.currency) else { return nil }
                guard filters.sku.isEmpty || matchesAny(row.productRef, in: filters.sku) else { return nil }
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
        descriptors: [AnalyticsReportDescriptor],
        resolvedApps: [ASCAppSummary]? = nil,
        freshnessCutoff: Date? = nil
    ) throws -> [QueryRecord] {
        let allowedSourceReports = Set(descriptors.map(\.id))
        let entries = try scopedManifestEntries(source: .analytics) { record in
            if let freshnessCutoff, record.fetchedAt < freshnessCutoff {
                return false
            }
            guard reportDateKey(record.reportDateKey, isWithin: window) else {
                return false
            }
            if let resolvedApps, resolvedApps.isEmpty == false,
               matchesResolvedAnalyticsEntry(record, resolvedApps: resolvedApps) == false {
                return false
            }
            return allowedSourceReports.contains(analyticsSourceReportID(for: record.reportType))
        }.sorted {
            if $0.fetchedAt == $1.fetchedAt {
                return $0.filePath < $1.filePath
            }
            return $0.fetchedAt < $1.fetchedAt
        }
        var latestRecordsByKey: [String: QueryRecord] = [:]
        for entry in entries {
            let parsed = try parseAnalyticsRecords(tsv: try loadFile(entry.filePath), reportName: entry.reportType)
            for record in parsed {
                let dedupeKey = normalizedGroupKey(record.dimensions)
                var dimensions = record.dimensions
                if let bundleID = nonEmptyString(entry.bundleID) {
                    dimensions["bundleID"] = bundleID
                }
                let enriched = QueryRecord(id: record.id, dimensions: dimensions, metrics: record.metrics)
                latestRecordsByKey[dedupeKey] = enriched
            }
        }
        return latestRecordsByKey.values.filter { record in
            guard let rawDate = record.dimensions["date"], let date = PTDate(rawDate).date else { return false }
            let day = Calendar.pacific.startOfDay(for: date)
            guard window.startDate <= day, day <= window.endDate else { return false }
            if filters.app.isEmpty == false {
                if let resolvedApps, resolvedApps.isEmpty == false {
                    let resolvedNames = resolvedApps.map(\.name)
                    if matchesAny(record.dimensions["app"] ?? "", in: resolvedNames) == false,
                       matchesAny(record.dimensions["appAppleIdentifier"] ?? "", in: filters.app) == false,
                       matchesAny(record.dimensions["bundleID"] ?? "", in: filters.app) == false {
                        return false
                    }
                } else if matchesAny(record.dimensions["app"] ?? "", in: filters.app) == false,
                          matchesAny(record.dimensions["appAppleIdentifier"] ?? "", in: filters.app) == false,
                          matchesAny(record.dimensions["bundleID"] ?? "", in: filters.app) == false {
                    return false
                }
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

    private func matchesResolvedAnalyticsEntry(
        _ record: CachedReportRecord,
        resolvedApps: [ASCAppSummary]
    ) -> Bool {
        let recordAppID = nonEmptyString(record.appID)
        let recordBundleID = nonEmptyString(record.bundleID)
        guard recordAppID != nil || recordBundleID != nil else {
            return false
        }
        return resolvedApps.contains { app in
            if let recordAppID, recordAppID == app.id {
                return true
            }
            if let recordBundleID, recordBundleID == app.bundleID {
                return true
            }
            return false
        }
    }

    private func parseAnalyticsRecords(tsv: String, reportName: String) throws -> [QueryRecord] {
        let lines = tsv.split(whereSeparator: \.isNewline).map(String.init).filter { $0.isEmpty == false }
        guard let headerLine = lines.first else { return [] }
        let delimiter: Character = headerLine.contains("\t") ? "\t" : ","
        let headers = parseDelimitedLine(headerLine, delimiter: delimiter).map(normalizeHeader)
        let sourceReportID = analyticsSourceReportID(for: reportName)
        return lines.dropFirst().compactMap { line in
            let cells = parseDelimitedLine(line, delimiter: delimiter)
            guard cells.count == headers.count else { return nil }
            var dimensions: [String: String] = [
                "reportType": normalizeReportName(reportName),
                "sourceReport": sourceReportID
            ]
            var metrics: [String: Double] = [:]
            for (header, rawValue) in zip(headers, cells) {
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if header == "date", let parsed = parseDate(trimmed) {
                    dimensions["date"] = parsed.ptDateString
                } else if let dimensionKey = analyticsDimensionKey(for: header), trimmed.isEmpty == false {
                    dimensions[dimensionKey] = trimmed
                } else if let value = Double(trimmed.replacingOccurrences(of: ",", with: "")) {
                    metrics[header] = value
                } else if trimmed.isEmpty == false {
                    dimensions[header] = trimmed
                }
            }
            guard dimensions["date"] != nil || metrics.isEmpty == false else { return nil }
            return QueryRecord(id: line.sha256Hex, dimensions: dimensions, metrics: metrics)
        }
    }

    private func analyticsDimensionKey(for header: String) -> String? {
        switch header {
        case "app name":
            return "app"
        case "app apple identifier":
            return "appAppleIdentifier"
        case "app version", "version":
            return "version"
        case "territory":
            return "territory"
        case "device":
            return "device"
        case "platform", "platform version":
            return "platform"
        default:
            return nil
        }
    }

    private func analyticsSourceReportID(for reportName: String) -> String {
        switch normalizeReportName(reportName) {
        case "app-store-downloads":
            return "acquisition"
        case "app-store-discovery-and-engagement":
            return "engagement"
        case "app-sessions":
            return "usage"
        case "app-crashes":
            return "performance"
        default:
            return normalizeReportName(reportName)
        }
    }

    private func appGroupValue(_ record: QueryRecord) -> String {
        let appName = nonEmptyString(record.dimensions["app"]) ?? nonEmptyString(record.dimensions["name"]) ?? ""
        let appAppleIdentifier = record.dimensions["appAppleIdentifier"] ?? ""
        let sourceReport = normalizeReportName(record.dimensions["sourceReport"] ?? "")
        if ["summary-sales", "pre-order", "subscription-offer-redemption"].contains(sourceReport),
           appAppleIdentifier.isEmpty == false {
            return appAppleIdentifier
        }
        guard appAppleIdentifier.isEmpty == false else { return appName }
        guard appName.isEmpty == false, appName != appAppleIdentifier else { return appAppleIdentifier }
        return "\(appName) (\(appAppleIdentifier))"
    }

    private func subscriptionGroupValue(_ record: QueryRecord) -> String {
        let subscriptionName = record.dimensions["subscription"] ?? ""
        let subscriptionAppleIdentifier = record.dimensions["subscriptionAppleIdentifier"] ?? record.dimensions["sku"] ?? ""
        guard subscriptionAppleIdentifier.isEmpty == false else { return subscriptionName }
        guard subscriptionName.isEmpty == false, subscriptionName != subscriptionAppleIdentifier else {
            return subscriptionAppleIdentifier
        }
        return "\(subscriptionName) (\(subscriptionAppleIdentifier))"
    }

    private func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                if isQuoted {
                    let nextIndex = line.index(after: index)
                    if nextIndex < line.endIndex, line[nextIndex] == "\"" {
                        current.append("\"")
                        index = line.index(after: nextIndex)
                        continue
                    }
                    isQuoted = false
                    index = line.index(after: index)
                    continue
                }
                if current.isEmpty {
                    isQuoted = true
                    index = line.index(after: index)
                    continue
                }
            }

            if character == delimiter, isQuoted == false {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }

        cells.append(current)
        return cells
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
                group[item.rawValue] = appGroupValue(record)
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
                group[item.rawValue] = subscriptionGroupValue(record)
            }
        }
        return group
    }

    private func makeRecordsTable(dataset: QueryDataset, records: [QueryRecord]) -> TableModel {
        let dimensionKeys = orderedDimensionKeys(Set(records.flatMap { $0.dimensions.keys }), dataset: dataset)
        let hiddenMetrics = hiddenTableMetricKeys(for: dataset)
        let metricKeys = orderedMetricKeys(
            Set(records.flatMap { $0.metrics.keys })
                .subtracting(Set(dimensionKeys))
                .subtracting(hiddenMetrics),
            dataset: dataset
        )
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

    private func makeAggregateTable(dataset: QueryDataset, rows: [QueryAggregateRow]) -> TableModel {
        let groupKeys = orderedDimensionKeys(Set(rows.flatMap { $0.group.keys }), dataset: dataset)
        let hiddenMetrics = hiddenTableMetricKeys(for: dataset)
        let metricKeys = orderedMetricKeys(
            Set(rows.flatMap { $0.metrics.keys })
                .subtracting(Set(groupKeys))
                .subtracting(hiddenMetrics),
            dataset: dataset
        )
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

    private func makeComparisonTable(dataset: QueryDataset, rows: [QueryComparisonRow]) -> TableModel {
        let groupKeys = orderedDimensionKeys(Set(rows.flatMap { $0.group.keys }), dataset: dataset)
        let hiddenMetrics = hiddenTableMetricKeys(for: dataset)
        let metricKeys = orderedMetricKeys(
            Set(rows.flatMap { $0.metrics.keys })
                .subtracting(hiddenMetrics),
            dataset: dataset
        )
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

    private func orderedDimensionKeys(_ keys: Set<String>, dataset: QueryDataset) -> [String] {
        let preferred = preferredDimensionOrder(for: dataset)
        return keys.sorted { lhs, rhs in
            columnSortKey(lhs, preferred: preferred) < columnSortKey(rhs, preferred: preferred)
        }
    }

    private func orderedMetricKeys(_ keys: Set<String>, dataset: QueryDataset) -> [String] {
        let preferred = preferredMetricOrder(for: dataset)
        return keys.sorted { lhs, rhs in
            columnSortKey(lhs, preferred: preferred) < columnSortKey(rhs, preferred: preferred)
        }
    }

    private func columnSortKey(_ key: String, preferred: [String]) -> (Int, String) {
        let rank = preferred.firstIndex(of: key) ?? preferred.count + 1
        return (rank, key)
    }

    private func preferredDimensionOrder(for dataset: QueryDataset) -> [String] {
        switch dataset {
        case .sales:
            return ["date", "fiscalMonth", "app", "version", "territory", "device", "currency", "customerCurrency", "sku", "subscription", "sourceReport", "reportType"]
        case .reviews:
            return ["date", "app", "territory", "rating", "responseState", "sourceReport", "reportType", "title", "reviewerNickname"]
        case .finance:
            return ["date", "fiscalMonth", "territory", "currency", "sku", "sourceReport", "reportType"]
        case .analytics:
            return ["date", "fiscalMonth", "app", "bundleID", "version", "territory", "device", "platform", "sourceReport", "reportType"]
        case .brief:
            return []
        }
    }

    private func preferredMetricOrder(for dataset: QueryDataset) -> [String] {
        switch dataset {
        case .sales:
            return ["proceeds", "sales", "units", "installs", "purchases", "refunds", "qualifiedConversions", "activeSubscriptions", "subscribers", "billingRetry", "gracePeriod"]
        case .reviews:
            return ["count", "averageRating", "repliedRate", "lowRatingRatio", "repliedCount", "lowRatingCount", "unresolvedCount"]
        case .finance:
            return ["proceeds", "amount", "units"]
        case .analytics:
            return ["impressions", "pageViews", "appUnits", "sessions", "crashes"]
        case .brief:
            return []
        }
    }

    private func hiddenTableMetricKeys(for dataset: QueryDataset) -> Set<String> {
        switch dataset {
        case .reviews:
            return ["rating"]
        default:
            return []
        }
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

    private func loadSalesSummaryRows(
        window: PTDateWindow,
        freshnessCutoff: Date? = nil
    ) throws -> [ParsedSalesRow] {
        let fullMonths = Set(fullFiscalMonthsContained(in: window))
        let salesEntries = deduplicatedCachedEntries(try scopedManifestEntries(source: .sales) {
            guard $0.reportType == "SALES" else { return false }
            if let freshnessCutoff, $0.fetchedAt < freshnessCutoff {
                return false
            }
            if $0.reportSubType == "SUMMARY_MONTHLY" {
                return fullMonths.contains($0.reportDateKey)
            }
            return reportDateKey($0.reportDateKey, isWithin: window)
        })
        let monthlyEntries = salesEntries.filter { $0.reportSubType == "SUMMARY_MONTHLY" }
        let dailyEntries = salesEntries.filter { $0.reportSubType != "SUMMARY_MONTHLY" }
        let monthsWithMonthly = Set(monthlyEntries.map(\.reportDateKey))

        var rows: [ParsedSalesRow] = []
        for entry in dailyEntries {
            let parsed = try parser.parseSales(tsv: try loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
            rows.append(contentsOf: parsed.filter { row in
                let fiscalMonth = row.businessDatePT.fiscalMonthString
                return fullMonths.contains(fiscalMonth) == false || monthsWithMonthly.contains(fiscalMonth) == false
            })
        }
        for entry in monthlyEntries where fullMonths.contains(entry.reportDateKey) {
            rows.append(contentsOf: try parser.parseSales(
                tsv: try loadFile(entry.filePath),
                fallbackDatePT: PTDate("\(entry.reportDateKey)-01").date
            ))
        }
        return rows
    }

    private func loadSalesGenericRows(
        window: PTDateWindow,
        reportType: String,
        freshnessCutoff: Date? = nil
    ) throws -> [ParsedSalesRow] {
        let entries = deduplicatedCachedEntries(try scopedManifestEntries(source: .sales) {
            guard $0.reportType == reportType else { return false }
            if let freshnessCutoff, $0.fetchedAt < freshnessCutoff {
                return false
            }
            return reportDateKey($0.reportDateKey, isWithin: window)
        })
        return try entries.flatMap { entry in
            try parser.parseSales(tsv: try loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func loadSubscriptionRows(
        window: PTDateWindow,
        reportType: String,
        freshnessCutoff: Date? = nil
    ) throws -> [ParsedSubscriptionRow] {
        let entries = deduplicatedCachedEntries(try scopedManifestEntries(source: .sales) {
            guard $0.reportType == reportType else { return false }
            if let freshnessCutoff, $0.fetchedAt < freshnessCutoff {
                return false
            }
            return reportDateKey($0.reportDateKey, isWithin: window)
        })
        return try entries.flatMap { entry in
            try parser.parseSubscription(tsv: try loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func loadSubscriptionEventRows(window: PTDateWindow, freshnessCutoff: Date? = nil) throws -> [ParsedSubscriptionEventRow] {
        let entries = deduplicatedCachedEntries(try scopedManifestEntries(source: .sales) {
            guard $0.reportType == "SUBSCRIPTION_EVENT" else { return false }
            if let freshnessCutoff, $0.fetchedAt < freshnessCutoff {
                return false
            }
            return reportDateKey($0.reportDateKey, isWithin: window)
        })
        return try entries.flatMap { entry in
            try parser.parseSubscriptionEvent(tsv: try loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func loadSubscriberRows(window: PTDateWindow, freshnessCutoff: Date? = nil) throws -> [ParsedSubscriberDailyRow] {
        let entries = deduplicatedCachedEntries(try scopedManifestEntries(source: .sales) {
            guard $0.reportType == "SUBSCRIBER" else { return false }
            if let freshnessCutoff, $0.fetchedAt < freshnessCutoff {
                return false
            }
            return reportDateKey($0.reportDateKey, isWithin: window)
        })
        return try entries.flatMap { entry in
            try parser.parseSubscriberDaily(tsv: try loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
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
        guard filters.currency.isEmpty || matchesAny(row.currencyOfProceeds, in: filters.currency) else { return nil }
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
                "appAppleIdentifier": row.parentIdentifier.isEmpty ? row.appleIdentifier : row.parentIdentifier,
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
        guard filters.currency.isEmpty || matchesAny(row.proceedsCurrency, in: filters.currency) else { return nil }
        guard filters.device.isEmpty || matchesAny(row.device, in: filters.device) else { return nil }
        guard filters.sku.isEmpty || matchesAny(row.subscriptionAppleID, in: filters.sku) else { return nil }
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
                "appAppleIdentifier": row.appAppleID,
                "sku": row.subscriptionAppleID,
                "subscription": row.subscriptionName,
                "subscriptionAppleIdentifier": row.subscriptionAppleID,
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
        guard filters.sku.isEmpty || matchesAny(row.subscriptionAppleID, in: filters.sku) else { return nil }
        guard filters.subscription.isEmpty || matchesAny(row.subscriptionName, in: filters.subscription) || matchesAny(row.subscriptionAppleID, in: filters.subscription) else { return nil }
        if filters.app.isEmpty == false,
           matchesAny(row.appName, in: filters.app) == false,
           matchesAny(row.appAppleID, in: filters.app) == false {
            return nil
        }
        return QueryRecord(
            id: row.lineHash,
            dimensions: [
                "date": row.businessDatePT.ptDateString,
                "app": row.appName,
                "appAppleIdentifier": row.appAppleID,
                "subscription": row.subscriptionName,
                "sku": row.subscriptionAppleID,
                "subscriptionAppleIdentifier": row.subscriptionAppleID,
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
        guard filters.sku.isEmpty || matchesAny(row.subscriptionAppleID, in: filters.sku) else { return nil }
        guard filters.subscription.isEmpty || matchesAny(row.subscriptionName, in: filters.subscription) || matchesAny(row.subscriptionAppleID, in: filters.subscription) else { return nil }
        if filters.app.isEmpty == false,
           matchesAny(row.appName, in: filters.app) == false,
           matchesAny(row.appAppleID, in: filters.app) == false {
            return nil
        }
        return QueryRecord(
            id: row.lineHash,
            dimensions: [
                "date": row.businessDatePT.ptDateString,
                "app": row.appName,
                "appAppleIdentifier": row.appAppleID,
                "subscription": row.subscriptionName,
                "sku": row.subscriptionAppleID,
                "subscriptionAppleIdentifier": row.subscriptionAppleID,
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

    private func loadFile(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        try LocalFileSecurity.validateOwnerOnlyFile(url)
        return try String(contentsOfFile: path, encoding: .utf8)
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

    private func normalizedReviewResponseState(_ value: String?) -> String? {
        guard let state = nonEmptyString(value) else { return nil }
        switch normalizeReportName(state) {
        case "responded":
            return "responded"
        case "unresponded":
            return "unresponded"
        default:
            return nil
        }
    }

    private func nonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        let spanDays = calendar.dateComponents([.day], from: current.window.startDate, to: current.window.endDate).day ?? 0
        guard let shiftedStart = calendar.date(byAdding: component, value: value, to: current.window.startDate),
              let shiftedEnd = calendar.date(byAdding: component, value: value, to: current.window.endDate)
        else {
            throw AnalyticsEngineError.invalidQuery("Unable to resolve comparison range.")
        }
        let start: Date
        let end: Date
        if let fullPeriodComponent = fullCalendarPeriodComponent(
            window: current.window,
            comparisonComponent: component,
            calendar: calendar
        ) {
            guard let shiftedInterval = calendar.dateInterval(of: fullPeriodComponent, for: shiftedStart),
                  let shiftedIntervalEnd = calendar.date(byAdding: .day, value: -1, to: shiftedInterval.end)
            else {
                throw AnalyticsEngineError.invalidQuery("Unable to resolve comparison range.")
            }
            start = shiftedInterval.start
            end = shiftedIntervalEnd
        } else if calendar.isDate(shiftedStart, inSameDayAs: shiftedEnd) {
            guard let spanPreservingStart = calendar.date(byAdding: .day, value: -spanDays, to: shiftedEnd) else {
                throw AnalyticsEngineError.invalidQuery("Unable to resolve comparison range.")
            }
            start = spanPreservingStart
            end = shiftedEnd
        } else {
            start = shiftedStart
            end = shiftedEnd
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

    private func scopedManifestEntries(
        source: ReportSource,
        matching include: (CachedReportRecord) -> Bool = { _ in true }
    ) throws -> [CachedReportRecord] {
        let entries = try cacheStore.loadManifest().filter { $0.source == source && include($0) }
        guard let vendorNumber else {
            let distinctVendors = Set(entries.compactMap { nonEmptyString($0.vendorNumber) })
            let hasLegacyEntries = entries.contains { nonEmptyString($0.vendorNumber) == nil }
            if distinctVendors.count > 1 {
                throw AnalyticsEngineError.invalidQuery(
                    "Cached \(source.rawValue) reports contain multiple vendor numbers. Set vendorNumber or clear the cache before querying."
                )
            }
            if hasLegacyEntries, distinctVendors.isEmpty == false {
                throw AnalyticsEngineError.invalidQuery(
                    "Cached \(source.rawValue) reports mix legacy unscoped entries with vendor-tagged entries. Set vendorNumber or clear the cache before querying."
                )
            }
            return entries
        }
        let scopedEntries = entries.filter { nonEmptyString($0.vendorNumber) == vendorNumber }
        let legacyEntries = entries.filter { nonEmptyString($0.vendorNumber) == nil }
        let otherScopedVendors = Set(entries.compactMap { record -> String? in
            guard let scopedVendor = nonEmptyString(record.vendorNumber), scopedVendor != vendorNumber else {
                return nil
            }
            return scopedVendor
        })

        if scopedEntries.isEmpty == false {
            if legacyEntries.isEmpty {
                return scopedEntries
            }
            if otherScopedVendors.isEmpty == false {
                throw AnalyticsEngineError.invalidQuery(
                    "Cached \(source.rawValue) reports mix legacy unscoped entries with vendor-tagged entries for multiple accounts. Clear the cache or resync before querying."
                )
            }
            return scopedEntries + legacyEntries
        }
        if otherScopedVendors.isEmpty {
            return legacyEntries
        }
        if legacyEntries.isEmpty {
            return []
        }
        throw AnalyticsEngineError.invalidQuery(
            "Cached \(source.rawValue) reports mix legacy unscoped entries with vendor-tagged entries for other accounts. Clear the cache or resync before querying."
        )
    }

    private func reportDateKey(_ reportDateKey: String, isWithin window: PTDateWindow) -> Bool {
        guard let date = PTDate(reportDateKey).date else {
            return false
        }
        return date >= window.startDate && date <= window.endDate
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

    private func deduplicatedCachedEntries(_ entries: [CachedReportRecord]) -> [CachedReportRecord] {
        var byKey: [String: CachedReportRecord] = [:]
        for entry in entries {
            let key = [
                entry.source.rawValue,
                entry.reportType,
                entry.reportSubType,
                entry.reportDateKey
            ].joined(separator: "|")
            guard let existing = byKey[key] else {
                byKey[key] = entry
                continue
            }
            byKey[key] = preferredCachedEntry(between: existing, and: entry)
        }
        return Array(byKey.values)
    }

    private func preferredCachedEntry(
        between lhs: CachedReportRecord,
        and rhs: CachedReportRecord
    ) -> CachedReportRecord {
        let lhsScoped = nonEmptyString(lhs.vendorNumber) != nil
        let rhsScoped = nonEmptyString(rhs.vendorNumber) != nil
        if lhsScoped != rhsScoped {
            return rhsScoped ? rhs : lhs
        }
        if lhs.fetchedAt != rhs.fetchedAt {
            return lhs.fetchedAt < rhs.fetchedAt ? rhs : lhs
        }
        return lhs.filePath <= rhs.filePath ? lhs : rhs
    }

    private func isFullCalendarPeriod(
        window: PTDateWindow,
        component: Calendar.Component,
        calendar: Calendar
    ) -> Bool {
        guard let interval = calendar.dateInterval(of: component, for: window.startDate) else {
            return false
        }
        let intervalEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return calendar.isDate(window.startDate, inSameDayAs: interval.start)
            && calendar.isDate(window.endDate, inSameDayAs: intervalEnd)
    }

    private func fullCalendarPeriodComponent(
        window: PTDateWindow,
        comparisonComponent: Calendar.Component,
        calendar: Calendar
    ) -> Calendar.Component? {
        switch comparisonComponent {
        case .month:
            return isFullCalendarPeriod(window: window, component: .month, calendar: calendar) ? .month : nil
        case .year:
            if isFullCalendarPeriod(window: window, component: .year, calendar: calendar) {
                return .year
            }
            if isFullCalendarPeriod(window: window, component: .month, calendar: calendar) {
                return .month
            }
            return nil
        default:
            return isFullCalendarPeriod(window: window, component: comparisonComponent, calendar: calendar)
                ? comparisonComponent
                : nil
        }
    }
}
