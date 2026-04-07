import Foundation
import ACDCore

public final class AnalyticsEngine {
    private let cacheStore: CacheStore
    private let parser: ReportParser
    private let fxService: FXRateService

    public init(
        cacheStore: CacheStore,
        parser: ReportParser = ReportParser(),
        fxService: FXRateService
    ) {
        self.cacheStore = cacheStore
        self.parser = parser
        self.fxService = fxService
    }

    public func snapshot(
        source: DashboardDataSource,
        filters: QueryFilters = QueryFilters()
    ) async throws -> DashboardSnapshot {
        switch source {
        case .sales:
            return try await loadSalesSnapshot(filters: filters)
        case .finance:
            return try await loadFinanceSnapshot(filters: filters)
        }
    }

    public func modules(filters: QueryFilters = QueryFilters()) async throws -> DashboardModuleSnapshot {
        let sales = try await loadSalesSnapshot(filters: filters)
        let finance = try await loadFinanceSnapshot(filters: filters)
        let subscriptions = try await loadSubscriptionHealth(filters: filters)
        let dataHealth = try health()

        let overview = ExecutiveOverviewSnapshot(
            salesBookingUSD: sales.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0,
            financeRecognizedUSD: finance.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0,
            netPaidUnits: sales.totalPurchases,
            refundUnits: sales.refundCount,
            conversion: sales.payingRate,
            salesChangeRatio: nil,
            financeChangeRatio: nil,
            asOfPT: maxOptionalDate(sales.dataAsOfPT, finance.dataAsOfPT),
            confidence: dataHealth.confidence
        )

        let growth = GrowthSnapshot(
            installs: sales.totalInstalls,
            purchaseUnits: sales.totalPurchases,
            refundUnits: sales.refundCount,
            conversion: sales.payingRate,
            topTerritories: try await topBreakdown(kind: .territory, filters: filters),
            topDevices: try await topBreakdown(kind: .device, filters: filters),
            topVersions: try await topBreakdown(kind: .version, filters: filters),
            trend: sales.trend,
            asOfPT: sales.dataAsOfPT,
            confidence: dataHealth.confidence
        )

        let financeModule = FinanceReconcileSnapshot(
            recognizedUSD: finance.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0,
            financeRows: try await financeRowCount(filters: filters),
            salesRows: try await salesRowCount(filters: filters),
            currencies: finance.proceedsByCurrency,
            monthlyDiffUSD: (sales.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0) - (finance.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0),
            asOfPT: finance.dataAsOfPT,
            confidence: dataHealth.confidence
        )

        return DashboardModuleSnapshot(
            overview: overview,
            growth: growth,
            subscription: subscriptions,
            finance: financeModule,
            dataHealth: dataHealth,
            generatedAt: Date()
        )
    }

    public func trend(
        source: DashboardDataSource,
        filters: QueryFilters = QueryFilters()
    ) async throws -> [TrendPoint] {
        try await snapshot(source: source, filters: filters).trend
    }

    public func topProducts(
        source: DashboardDataSource,
        filters: QueryFilters = QueryFilters()
    ) async throws -> [TopProductRow] {
        let rows = try await snapshot(source: source, filters: filters).topProducts
        if let limit = filters.limit {
            return Array(rows.prefix(max(0, limit)))
        }
        return rows
    }

    public func health(reference: Date = Date()) throws -> DataHealthSnapshot {
        let manifest = try cacheStore.loadManifest()
        let salesDates = manifest
            .filter { $0.source == .sales && $0.reportType == "SALES" && $0.reportSubType != "SUMMARY_MONTHLY" }
            .compactMap { PTDate($0.reportDateKey).date }
        let monthlyFinance = manifest
            .filter { $0.source == .finance }
            .map(\.reportDateKey)
            .filter { $0.count >= 7 }

        let subscriptionDates = manifest
            .filter { $0.reportType == "SUBSCRIPTION" }
            .compactMap { PTDate($0.reportDateKey).date }

        let salesAsOf = salesDates.max()
        let subscriptionAsOf = subscriptionDates.max()
        let financeAsOf = monthlyFinance.compactMap { DateFormatter.fiscalMonthFormatter.date(from: String($0.prefix(7))) }.max()
        let salesLagDays = lagDays(from: salesAsOf, reference: reference)
        let subscriptionLagDays = lagDays(from: subscriptionAsOf, reference: reference)
        let financeLagMonths = lagMonths(from: financeAsOf, reference: reference)

        var issues: [String] = []
        if salesAsOf == nil { issues.append("Missing sales reports.") }
        if subscriptionAsOf == nil { issues.append("Missing subscription reports.") }
        if financeAsOf == nil { issues.append("Missing finance reports.") }

        let confidence: MetricConfidence
        if issues.isEmpty, salesLagDays <= 2, financeLagMonths <= 1 {
            confidence = .high
        } else if issues.count <= 1 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return DataHealthSnapshot(
            salesAsOfPT: salesAsOf,
            subscriptionAsOfPT: subscriptionAsOf,
            financeAsOfPT: financeAsOf,
            salesCoverageDays: Set(salesDates.map(\.ptDateString)).count,
            subscriptionCoverageDays: Set(subscriptionDates.map(\.ptDateString)).count,
            financeCoverageMonths: Set(monthlyFinance.map { String($0.prefix(7)) }).count,
            unknownCurrencyRatio: 0,
            salesLagDays: salesLagDays,
            subscriptionLagDays: subscriptionLagDays,
            financeLagMonths: financeLagMonths,
            confidence: confidence,
            issues: issues
        )
    }

    public func reviews() throws -> [ASCLatestReview] {
        (try cacheStore.loadReviews()?.reviews ?? []).sorted { $0.createdDate > $1.createdDate }
    }

    public func reviewsSummary() throws -> ReviewsSummarySnapshot {
        let reviews = try reviews()
        let summary = ASCRatingsSummary.fromReviews(reviews)
        let byTerritory = Dictionary(grouping: reviews, by: { ($0.territory ?? "UNK").uppercased() })
            .map { BreakdownEntry(key: $0.key, value: Double($0.value.count)) }
            .sorted { $0.value > $1.value }
        let unresolvedResponses = reviews.filter { $0.developerResponse == nil }.count
        return ReviewsSummarySnapshot(
            total: reviews.count,
            averageRating: summary.averageRating,
            histogram: summary.normalizedStarCounts,
            byTerritory: byTerritory,
            unresolvedResponses: unresolvedResponses,
            latestDate: reviews.first?.createdDate
        )
    }

    public func audit() async throws -> DoctorAuditSnapshot {
        let manifest = try cacheStore.loadManifest()
        let duplicates = Dictionary(grouping: manifest, by: \.id)
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
        let reviewsCount = try reviews().count
        let latestSalesDate = manifest
            .filter { $0.source == .sales && $0.reportDateKey.count == 10 }
            .map(\.reportDateKey)
            .max()
        let latestFinanceMonth = manifest
            .filter { $0.source == .finance }
            .map { String($0.reportDateKey.prefix(7)) }
            .max()

        let salesRows = try await loadSalesRows(filters: QueryFilters(), includeMonthly: true)
        let financeRows = try await loadFinanceRows(filters: QueryFilters())
        let unknownCurrencyRows = salesRows.filter { $0.currencyOfProceeds.isUnknownCurrencyCode }.count
            + financeRows.filter { $0.currency.isUnknownCurrencyCode }.count

        return DoctorAuditSnapshot(
            totalReports: manifest.count,
            totalReviewItems: reviewsCount,
            unknownCurrencyRows: unknownCurrencyRows,
            duplicateReportKeys: duplicates,
            latestSalesDatePT: latestSalesDate,
            latestFinanceMonth: latestFinanceMonth
        )
    }

    public func reconcile(filters: QueryFilters = QueryFilters()) async throws -> ReconcileSnapshot {
        let sales = try await loadSalesSnapshot(filters: filters)
        let finance = try await loadFinanceSnapshot(filters: filters)
        let salesUSD = sales.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0
        let financeUSD = finance.proceedsByCurrency.first(where: { $0.currency == "USD" })?.amount ?? 0
        return ReconcileSnapshot(
            salesUSD: salesUSD,
            financeUSD: financeUSD,
            diffUSD: salesUSD - financeUSD,
            currencies: finance.proceedsByCurrency
        )
    }

    private func loadSalesSnapshot(filters: QueryFilters) async throws -> DashboardSnapshot {
        let rows = try await loadSalesRows(filters: filters, includeMonthly: true)
        let range = resolvedRange(filters: filters, dates: rows.map(\.businessDatePT))
        let filteredRows = rows.filter { row in
            guard inRange(row.businessDatePT, range: range) else { return false }
            if let territory = normalized(filters.territory), territory.isEmpty == false, row.territory.uppercased() != territory {
                return false
            }
            if let device = normalized(filters.device), device.isEmpty == false, row.device.lowercased() != device.lowercased() {
                return false
            }
            return true
        }

        let requests = Set(filteredRows.map { FXLookupRequest(dateKey: $0.businessDatePT.ptDateString, currencyCode: $0.currencyOfProceeds) })
        let fxRates = try await fxService.resolveUSDRates(for: requests)

        var proceedsByCurrency: [String: Double] = [:]
        var trendAccumulator: [Date: (units: Double, proceedsUSD: Double)] = [:]
        var topAccumulator: [String: (name: String, kind: ProductKind, proceedsUSD: Double, units: Double)] = [:]
        var totalInstalls = 0.0
        var totalPurchases = 0.0
        var totalNonRenewPurchases = 0.0
        var totalQualifiedConversions = 0.0
        var refundCount = 0.0

        for row in filteredRows {
            let originalCurrency = row.currencyOfProceeds.normalizedCurrencyCode
            let originalProceeds = row.units * row.developerProceedsPerUnit
            proceedsByCurrency[originalCurrency, default: 0] += originalProceeds

            let fxRate = fxRates[FXLookupRequest(dateKey: row.businessDatePT.ptDateString, currencyCode: row.currencyOfProceeds)] ?? 0
            let proceedsUSD = originalProceeds * fxRate
            proceedsByCurrency["USD", default: 0] += proceedsUSD

            let unitsForMetrics = salesDisplayUnits(row)
            let installUnits = salesInstallUnits(row)
            let purchaseUnits = salesPurchaseUnits(row)
            let kind = classifyProduct(productTypeIdentifier: row.productTypeIdentifier, parentIdentifier: row.parentIdentifier)
            let productKey = row.sku.isEmpty ? (row.appleIdentifier.isEmpty ? row.title : row.appleIdentifier) : row.sku
            var entry = topAccumulator[productKey] ?? (
                name: row.title.isEmpty ? productKey : row.title,
                kind: kind,
                proceedsUSD: 0,
                units: 0
            )
            entry.units += unitsForMetrics
            entry.proceedsUSD += proceedsUSD
            topAccumulator[productKey] = entry

            totalInstalls += max(0, installUnits)
            let positivePurchaseUnits = max(0, purchaseUnits)
            totalPurchases += positivePurchaseUnits
            if isRenewalPurchase(row) == false {
                totalNonRenewPurchases += positivePurchaseUnits
            }
            totalQualifiedConversions += max(0, salesQualifiedConversionUnits(row))
            if salesUnitsForMetrics(row) < 0 {
                refundCount += abs(salesUnitsForMetrics(row))
            }

            let day = Calendar.pacific.startOfDay(for: row.businessDatePT)
            var trend = trendAccumulator[day] ?? (0, 0)
            trend.units += unitsForMetrics
            trend.proceedsUSD += proceedsUSD
            trendAccumulator[day] = trend
        }

        var membership = MembershipBreakdown.zero
        for row in filteredRows {
            let purchaseUnits = max(0, salesPurchaseUnits(row))
            guard purchaseUnits > 0, let tier = classifyMembershipTier(title: row.title, sku: row.sku) else { continue }
            switch tier {
            case .lifetime:
                membership.lifetime += purchaseUnits
            case .yearly:
                membership.yearly += purchaseUnits
            case .monthly:
                membership.monthly += purchaseUnits
            }
        }

        let trend = trendAccumulator.map { date, value in
            TrendPoint(date: date, units: value.units, proceedsByCurrency: ["USD": value.proceedsUSD])
        }.sorted { $0.date < $1.date }

        let topProducts = topAccumulator.map { key, value in
            TopProductRow(id: key, name: value.name, kind: value.kind, proceeds: value.proceedsUSD, currency: "USD", units: value.units)
        }
        .sorted { $0.proceeds > $1.proceeds }

        let latestWindow = makeLatestWindow(
            rows: filteredRows.map { row in
                let proceedsUSD = (fxRates[FXLookupRequest(dateKey: row.businessDatePT.ptDateString, currencyCode: row.currencyOfProceeds)] ?? 0) * row.units * row.developerProceedsPerUnit
                return (
                    date: row.businessDatePT,
                    units: salesDisplayUnits(row),
                    purchases: salesPurchaseUnits(row),
                    kind: classifyProduct(productTypeIdentifier: row.productTypeIdentifier, parentIdentifier: row.parentIdentifier),
                    proceedsUSD: proceedsUSD
                )
            }
        )

        let sortedCurrencies = proceedsByCurrency.map { CurrencyAmount(currency: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
        let totalUnits = filteredRows.reduce(0) { $0 + salesDisplayUnits($1) }
        let payingRate = totalInstalls > 0 ? (totalPurchases / totalInstalls) : 0

        return DashboardSnapshot(
            source: .sales,
            totalUnits: totalUnits,
            totalInstalls: totalInstalls,
            totalPurchases: totalPurchases,
            totalNonRenewPurchases: totalNonRenewPurchases,
            totalQualifiedConversions: totalQualifiedConversions,
            payingRate: payingRate,
            membershipBreakdown: membership,
            refundCount: refundCount,
            proceedsByCurrency: sortedCurrencies,
            trend: trend,
            topProducts: Array(topProducts.prefix(max(1, filters.limit ?? 30))),
            dataAsOfPT: filteredRows.map(\.businessDatePT).max(),
            lastRefresh: try cacheStore.loadManifest().map(\.fetchedAt).max(),
            latestWindow: latestWindow,
            rangeStartPT: range?.lowerBound,
            rangeEndPT: range?.upperBound
        )
    }

    private func loadFinanceSnapshot(filters: QueryFilters) async throws -> DashboardSnapshot {
        let rows = try await loadFinanceRows(filters: filters)
        let range = resolvedRange(filters: filters, dates: rows.map(\.businessDatePT))
        let filteredRows = rows.filter { inRange($0.businessDatePT, range: range) }

        let requests = Set(filteredRows.map { FXLookupRequest(dateKey: ($0.transactionDatePT ?? $0.businessDatePT).ptDateString, currencyCode: $0.currency) })
        let fxRates = try await fxService.resolveUSDRates(for: requests)

        var proceedsByCurrency: [String: Double] = [:]
        var trendAccumulator: [Date: (units: Double, proceedsUSD: Double)] = [:]
        var topAccumulator: [String: (name: String, proceedsUSD: Double, units: Double)] = [:]
        var totalPurchases = 0.0

        for row in filteredRows {
            let currency = row.currency.normalizedCurrencyCode
            proceedsByCurrency[currency, default: 0] += row.amount
            let fxDate = (row.transactionDatePT ?? row.businessDatePT).ptDateString
            let proceedsUSD = row.amount * (fxRates[FXLookupRequest(dateKey: fxDate, currencyCode: row.currency)] ?? 0)
            proceedsByCurrency["USD", default: 0] += proceedsUSD

            let monthDate = DateFormatter.fiscalMonthFormatter.date(from: row.fiscalMonth) ?? row.businessDatePT
            var trend = trendAccumulator[monthDate] ?? (0, 0)
            trend.units += row.units
            trend.proceedsUSD += proceedsUSD
            trendAccumulator[monthDate] = trend

            let key = row.productRef.isEmpty ? "Unknown" : row.productRef
            var top = topAccumulator[key] ?? (key, 0, 0)
            top.units += row.units
            top.proceedsUSD += proceedsUSD
            topAccumulator[key] = top
            totalPurchases += max(0, row.units)
        }

        let trend = trendAccumulator.map { date, value in
            TrendPoint(date: date, units: value.units, proceedsByCurrency: ["USD": value.proceedsUSD])
        }.sorted { $0.date < $1.date }

        let topProducts = topAccumulator.map { key, value in
            TopProductRow(id: key, name: value.name, kind: .other, proceeds: value.proceedsUSD, currency: "USD", units: value.units)
        }.sorted { $0.proceeds > $1.proceeds }

        let latestWindow = makeLatestWindow(
            rows: filteredRows.map { row in
                let fxDate = (row.transactionDatePT ?? row.businessDatePT).ptDateString
                let proceedsUSD = row.amount * (fxRates[FXLookupRequest(dateKey: fxDate, currencyCode: row.currency)] ?? 0)
                return (row.businessDatePT, row.units, max(0, row.units), ProductKind.other, proceedsUSD)
            }
        )

        return DashboardSnapshot(
            source: .finance,
            totalUnits: filteredRows.reduce(0) { $0 + $1.units },
            totalInstalls: 0,
            totalPurchases: totalPurchases,
            totalNonRenewPurchases: 0,
            totalQualifiedConversions: 0,
            payingRate: 0,
            membershipBreakdown: .zero,
            refundCount: 0,
            proceedsByCurrency: proceedsByCurrency.map { CurrencyAmount(currency: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount },
            trend: trend,
            topProducts: Array(topProducts.prefix(max(1, filters.limit ?? 30))),
            dataAsOfPT: filteredRows.map(\.businessDatePT).max(),
            lastRefresh: try cacheStore.loadManifest().map(\.fetchedAt).max(),
            latestWindow: latestWindow,
            rangeStartPT: range?.lowerBound,
            rangeEndPT: range?.upperBound
        )
    }

    private func loadSubscriptionHealth(filters: QueryFilters) async throws -> SubscriptionHealthSnapshot {
        let rows = try await loadSubscriptionRows(filters: filters)
        let range = resolvedRange(filters: filters, dates: rows.map(\.businessDatePT))
        let filteredRows = rows.filter { inRange($0.businessDatePT, range: range) }

        let activeSubscriptions = filteredRows.reduce(0) {
            $0 + $1.activeStandard + $1.activeIntroTrial + $1.activeIntroPayUpFront + $1.activeIntroPayAsYouGo
        }
        let billingRetry = filteredRows.reduce(0) { $0 + $1.billingRetry }
        let gracePeriod = filteredRows.reduce(0) { $0 + $1.gracePeriod }
        let subscribersRaw = filteredRows.reduce(0) { $0 + $1.subscribersRaw }
        let dailyTrend = Dictionary(grouping: filteredRows, by: { Calendar.pacific.startOfDay(for: $0.businessDatePT) })
            .map { date, dayRows in
                TrendPoint(
                    date: date,
                    units: dayRows.reduce(0) { $0 + $1.activeStandard + $1.activeIntroTrial + $1.activeIntroPayUpFront + $1.activeIntroPayAsYouGo },
                    proceedsByCurrency: [:]
                )
            }
            .sorted { $0.date < $1.date }
        let byCountry = Dictionary(grouping: filteredRows, by: { $0.country.uppercased() })
            .map { BreakdownEntry(key: $0.key, value: $0.value.reduce(0) { $0 + $1.activeStandard }) }
            .sorted { $0.value > $1.value }
        let byDevice = Dictionary(grouping: filteredRows, by: { $0.device })
            .map { BreakdownEntry(key: $0.key, value: $0.value.reduce(0) { $0 + $1.activeStandard }) }
            .sorted { $0.value > $1.value }
        return SubscriptionHealthSnapshot(
            activeSubscriptions: activeSubscriptions,
            billingRetry: billingRetry,
            gracePeriod: gracePeriod,
            subscribersRaw: subscribersRaw,
            activeByCountry: byCountry,
            activeByDevice: byDevice,
            retryRate: activeSubscriptions > 0 ? billingRetry / activeSubscriptions : 0,
            graceRate: activeSubscriptions > 0 ? gracePeriod / activeSubscriptions : 0,
            dailyTrend: dailyTrend,
            asOfPT: filteredRows.map(\.businessDatePT).max(),
            confidence: filteredRows.isEmpty ? .low : .medium
        )
    }

    private func loadSalesRows(filters: QueryFilters, includeMonthly: Bool) async throws -> [ParsedSalesRow] {
        let manifest = try cacheStore.loadManifest()
        let salesEntries = manifest.filter { record in
            guard record.source == .sales, record.reportType == "SALES" else { return false }
            if includeMonthly == false, record.reportSubType == "SUMMARY_MONTHLY" { return false }
            return true
        }

        let monthlyEntries = salesEntries.filter { $0.reportSubType == "SUMMARY_MONTHLY" }
        let dailyEntries = salesEntries.filter { $0.reportSubType != "SUMMARY_MONTHLY" }
        let range = explicitRange(filters: filters)
        let fullMonths = range.map(fullMonthsContained) ?? []

        var rows: [ParsedSalesRow] = []
        for entry in dailyEntries {
            let parsed = try parser.parseSales(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
            rows.append(contentsOf: parsed.filter { row in
                let fiscalMonth = row.businessDatePT.fiscalMonthString
                return fullMonths.contains(fiscalMonth) == false
            })
        }

        for entry in monthlyEntries where fullMonths.contains(entry.reportDateKey) {
            rows.append(contentsOf: try parser.parseSales(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate("\(entry.reportDateKey)-01").date))
        }
        return rows
    }

    private func loadFinanceRows(filters: QueryFilters) async throws -> [ParsedFinanceRow] {
        let manifest = try cacheStore.loadManifest()
        let entries = manifest.filter { $0.source == .finance }
        var rows: [ParsedFinanceRow] = []
        for entry in entries {
            let fiscalMonth = String(entry.reportDateKey.prefix(7))
            rows.append(
                contentsOf: try parser.parseFinance(
                    tsv: loadFile(entry.filePath),
                    fiscalMonth: fiscalMonth,
                    regionCode: entry.reportSubType,
                    vendorNumber: entry.vendorNumber,
                    reportVariant: entry.reportSubType
                )
            )
        }
        return rows
    }

    private func loadSubscriptionRows(filters: QueryFilters) async throws -> [ParsedSubscriptionRow] {
        let manifest = try cacheStore.loadManifest()
        let entries = manifest.filter { $0.source == .sales && $0.reportType == "SUBSCRIPTION" }
        return try entries.flatMap { entry in
            try parser.parseSubscription(tsv: loadFile(entry.filePath), fallbackDatePT: PTDate(entry.reportDateKey).date)
        }
    }

    private func topBreakdown(kind: BreakdownKind, filters: QueryFilters) async throws -> [BreakdownEntry] {
        let rows = try await loadSalesRows(filters: filters, includeMonthly: false)
        let range = resolvedRange(filters: filters, dates: rows.map(\.businessDatePT))
        let filteredRows = rows.filter { inRange($0.businessDatePT, range: range) }
        switch kind {
        case .territory:
            return Dictionary(grouping: filteredRows, by: { $0.territory.uppercased() })
                .map { BreakdownEntry(key: $0.key, value: $0.value.reduce(0) { $0 + max(0, salesDisplayUnits($1)) }) }
                .sorted { $0.value > $1.value }
        case .device:
            return Dictionary(grouping: filteredRows, by: { $0.device })
                .map { BreakdownEntry(key: $0.key, value: $0.value.reduce(0) { $0 + max(0, salesDisplayUnits($1)) }) }
                .sorted { $0.value > $1.value }
        case .version:
            return Dictionary(grouping: filteredRows, by: { $0.version.isEmpty ? "Unknown" : $0.version })
                .map { BreakdownEntry(key: $0.key, value: $0.value.reduce(0) { $0 + max(0, salesDisplayUnits($1)) }) }
                .sorted { $0.value > $1.value }
        }
    }

    private func salesRowCount(filters: QueryFilters) async throws -> Int {
        try await loadSalesRows(filters: filters, includeMonthly: true).count
    }

    private func financeRowCount(filters: QueryFilters) async throws -> Int {
        try await loadFinanceRows(filters: filters).count
    }

    private func loadFile(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func resolvedRange(filters: QueryFilters, dates: [Date]) -> ClosedRange<Date>? {
        if let explicit = explicitRange(filters: filters) {
            return explicit
        }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return nil }
        return Calendar.pacific.startOfDay(for: minDate)...Calendar.pacific.startOfDay(for: maxDate)
    }

    private func explicitRange(filters: QueryFilters) -> ClosedRange<Date>? {
        guard let startRaw = filters.startDatePT, let endRaw = filters.endDatePT,
              let start = PTDate(startRaw).date, let end = PTDate(endRaw).date else {
            return nil
        }
        let lower = min(start, end)
        let upper = max(start, end)
        return Calendar.pacific.startOfDay(for: lower)...Calendar.pacific.startOfDay(for: upper)
    }

    private func inRange(_ date: Date, range: ClosedRange<Date>?) -> Bool {
        guard let range else { return true }
        let normalized = Calendar.pacific.startOfDay(for: date)
        return range.contains(normalized)
    }

    private func fullMonthsContained(in range: ClosedRange<Date>) -> Set<String> {
        var result: Set<String> = []
        let calendar = Calendar.pacific
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: range.lowerBound)) ?? range.lowerBound
        while cursor <= range.upperBound {
            guard let monthInterval = calendar.dateInterval(of: .month, for: cursor) else { break }
            let monthStart = calendar.startOfDay(for: monthInterval.start)
            let monthEnd = calendar.startOfDay(for: (calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end))
            if range.lowerBound <= monthStart && range.upperBound >= monthEnd {
                result.insert(monthStart.fiscalMonthString)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
            cursor = next
        }
        return result
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

    private enum MembershipTier {
        case lifetime
        case yearly
        case monthly
    }

    private enum BreakdownKind {
        case territory
        case device
        case version
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

    private func salesDisplayUnits(_ row: ParsedSalesRow) -> Double {
        salesInstallUnits(row) + salesPurchaseUnits(row)
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

    private func isLifetimePurchase(_ row: ParsedSalesRow) -> Bool {
        classifyMembershipTier(title: row.title, sku: row.sku) == .lifetime
    }

    private func isRenewalPurchase(_ row: ParsedSalesRow) -> Bool {
        let orderType = row.orderType.lowercased()
        if orderType.contains("renew") { return true }
        let proceedsReason = row.proceedsReason.lowercased()
        return proceedsReason.contains("renew")
    }

    private func makeLatestWindow(
        rows: [(date: Date, units: Double, purchases: Double, kind: ProductKind, proceedsUSD: Double)]
    ) -> LatestWindowSnapshot? {
        guard rows.isEmpty == false else { return nil }
        let latestDay = rows.map { Calendar.pacific.startOfDay(for: $0.date) }.max()
        guard let latestDay else { return nil }
        let dayRows = rows.filter { Calendar.pacific.startOfDay(for: $0.date) == latestDay }
        return LatestWindowSnapshot(
            date: latestDay,
            units: dayRows.reduce(0) { $0 + $1.units },
            purchases: dayRows.reduce(0) { $0 + max(0, $1.purchases) },
            proceedsUSD: dayRows.reduce(0) { $0 + $1.proceedsUSD }
        )
    }

    private func lagDays(from value: Date?, reference: Date) -> Int {
        guard let value else { return 0 }
        return max(0, Calendar.pacific.dateComponents([.day], from: Calendar.pacific.startOfDay(for: value), to: Calendar.pacific.startOfDay(for: reference)).day ?? 0)
    }

    private func lagMonths(from value: Date?, reference: Date) -> Int {
        guard let value else { return 0 }
        let start = DateFormatter.fiscalMonthFormatter.date(from: value.fiscalMonthString) ?? value
        let end = DateFormatter.fiscalMonthFormatter.date(from: reference.fiscalMonthString) ?? reference
        return max(0, Calendar.pacific.dateComponents([.month], from: start, to: end).month ?? 0)
    }

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func maxOptionalDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
