import Foundation
import ACDCore

public enum DashboardDataSource: String, Codable, CaseIterable, Sendable {
    case sales
    case finance
}

public enum ProductKind: String, Codable, Sendable {
    case app
    case iap
    case subscription
    case other
}

public struct CurrencyAmount: Identifiable, Hashable, Codable, Sendable {
    public let currency: String
    public let amount: Double
    public var id: String { currency }

    public init(currency: String, amount: Double) {
        self.currency = currency
        self.amount = amount
    }
}

public struct TrendPoint: Identifiable, Hashable, Codable, Sendable {
    public var date: Date
    public var units: Double
    public var proceedsByCurrency: [String: Double]
    public var id: Date { date }

    public init(date: Date, units: Double, proceedsByCurrency: [String: Double]) {
        self.date = date
        self.units = units
        self.proceedsByCurrency = proceedsByCurrency
    }
}

public struct BreakdownEntry: Identifiable, Hashable, Codable, Sendable {
    public var key: String
    public var value: Double
    public var id: String { key }

    public init(key: String, value: Double) {
        self.key = key
        self.value = value
    }
}

public struct TopProductRow: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var kind: ProductKind
    public var proceeds: Double
    public var currency: String
    public var units: Double

    public init(
        id: String,
        name: String,
        kind: ProductKind,
        proceeds: Double,
        currency: String,
        units: Double
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.proceeds = proceeds
        self.currency = currency
        self.units = units
    }
}

public struct MembershipBreakdown: Hashable, Codable, Sendable {
    public var lifetime: Double
    public var yearly: Double
    public var monthly: Double

    public init(lifetime: Double, yearly: Double, monthly: Double) {
        self.lifetime = lifetime
        self.yearly = yearly
        self.monthly = monthly
    }

    public static let zero = MembershipBreakdown(lifetime: 0, yearly: 0, monthly: 0)
}

public struct LatestWindowSnapshot: Hashable, Codable, Sendable {
    public var date: Date
    public var units: Double
    public var purchases: Double
    public var proceedsUSD: Double

    public init(date: Date, units: Double, purchases: Double, proceedsUSD: Double) {
        self.date = date
        self.units = units
        self.purchases = purchases
        self.proceedsUSD = proceedsUSD
    }
}

public enum MetricConfidence: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low
}

public struct DataHealthSnapshot: Codable, Equatable, Sendable {
    public var salesAsOfPT: Date?
    public var subscriptionAsOfPT: Date?
    public var financeAsOfPT: Date?
    public var salesCoverageDays: Int
    public var subscriptionCoverageDays: Int
    public var financeCoverageMonths: Int
    public var unknownCurrencyRatio: Double
    public var salesLagDays: Int
    public var subscriptionLagDays: Int
    public var financeLagMonths: Int
    public var confidence: MetricConfidence
    public var issues: [String]

    public init(
        salesAsOfPT: Date?,
        subscriptionAsOfPT: Date?,
        financeAsOfPT: Date?,
        salesCoverageDays: Int,
        subscriptionCoverageDays: Int,
        financeCoverageMonths: Int,
        unknownCurrencyRatio: Double,
        salesLagDays: Int,
        subscriptionLagDays: Int,
        financeLagMonths: Int,
        confidence: MetricConfidence,
        issues: [String]
    ) {
        self.salesAsOfPT = salesAsOfPT
        self.subscriptionAsOfPT = subscriptionAsOfPT
        self.financeAsOfPT = financeAsOfPT
        self.salesCoverageDays = salesCoverageDays
        self.subscriptionCoverageDays = subscriptionCoverageDays
        self.financeCoverageMonths = financeCoverageMonths
        self.unknownCurrencyRatio = unknownCurrencyRatio
        self.salesLagDays = salesLagDays
        self.subscriptionLagDays = subscriptionLagDays
        self.financeLagMonths = financeLagMonths
        self.confidence = confidence
        self.issues = issues
    }

    public static let empty = DataHealthSnapshot(
        salesAsOfPT: nil,
        subscriptionAsOfPT: nil,
        financeAsOfPT: nil,
        salesCoverageDays: 0,
        subscriptionCoverageDays: 0,
        financeCoverageMonths: 0,
        unknownCurrencyRatio: 0,
        salesLagDays: 0,
        subscriptionLagDays: 0,
        financeLagMonths: 0,
        confidence: .low,
        issues: []
    )
}

public struct DashboardSnapshot: Codable, Sendable {
    public var source: DashboardDataSource
    public var totalUnits: Double
    public var totalInstalls: Double
    public var totalPurchases: Double
    public var totalNonRenewPurchases: Double
    public var totalQualifiedConversions: Double
    public var payingRate: Double
    public var membershipBreakdown: MembershipBreakdown
    public var refundCount: Double
    public var proceedsByCurrency: [CurrencyAmount]
    public var trend: [TrendPoint]
    public var topProducts: [TopProductRow]
    public var dataAsOfPT: Date?
    public var lastRefresh: Date?
    public var latestWindow: LatestWindowSnapshot?
    public var rangeStartPT: Date?
    public var rangeEndPT: Date?

    public init(
        source: DashboardDataSource,
        totalUnits: Double,
        totalInstalls: Double,
        totalPurchases: Double,
        totalNonRenewPurchases: Double,
        totalQualifiedConversions: Double,
        payingRate: Double,
        membershipBreakdown: MembershipBreakdown,
        refundCount: Double,
        proceedsByCurrency: [CurrencyAmount],
        trend: [TrendPoint],
        topProducts: [TopProductRow],
        dataAsOfPT: Date?,
        lastRefresh: Date?,
        latestWindow: LatestWindowSnapshot?,
        rangeStartPT: Date?,
        rangeEndPT: Date?
    ) {
        self.source = source
        self.totalUnits = totalUnits
        self.totalInstalls = totalInstalls
        self.totalPurchases = totalPurchases
        self.totalNonRenewPurchases = totalNonRenewPurchases
        self.totalQualifiedConversions = totalQualifiedConversions
        self.payingRate = payingRate
        self.membershipBreakdown = membershipBreakdown
        self.refundCount = refundCount
        self.proceedsByCurrency = proceedsByCurrency
        self.trend = trend
        self.topProducts = topProducts
        self.dataAsOfPT = dataAsOfPT
        self.lastRefresh = lastRefresh
        self.latestWindow = latestWindow
        self.rangeStartPT = rangeStartPT
        self.rangeEndPT = rangeEndPT
    }
}

public struct ExecutiveOverviewSnapshot: Codable, Sendable {
    public var salesBookingUSD: Double
    public var financeRecognizedUSD: Double
    public var netPaidUnits: Double
    public var refundUnits: Double
    public var conversion: Double
    public var salesChangeRatio: Double?
    public var financeChangeRatio: Double?
    public var asOfPT: Date?
    public var confidence: MetricConfidence

    public static let empty = ExecutiveOverviewSnapshot(
        salesBookingUSD: 0,
        financeRecognizedUSD: 0,
        netPaidUnits: 0,
        refundUnits: 0,
        conversion: 0,
        salesChangeRatio: nil,
        financeChangeRatio: nil,
        asOfPT: nil,
        confidence: .low
    )
}

public struct GrowthSnapshot: Codable, Sendable {
    public var installs: Double
    public var purchaseUnits: Double
    public var refundUnits: Double
    public var conversion: Double
    public var topTerritories: [BreakdownEntry]
    public var topDevices: [BreakdownEntry]
    public var topVersions: [BreakdownEntry]
    public var trend: [TrendPoint]
    public var asOfPT: Date?
    public var confidence: MetricConfidence

    public static let empty = GrowthSnapshot(
        installs: 0,
        purchaseUnits: 0,
        refundUnits: 0,
        conversion: 0,
        topTerritories: [],
        topDevices: [],
        topVersions: [],
        trend: [],
        asOfPT: nil,
        confidence: .low
    )
}

public struct SubscriptionHealthSnapshot: Codable, Sendable {
    public var activeSubscriptions: Double
    public var billingRetry: Double
    public var gracePeriod: Double
    public var subscribersRaw: Double
    public var activeByCountry: [BreakdownEntry]
    public var activeByDevice: [BreakdownEntry]
    public var retryRate: Double
    public var graceRate: Double
    public var dailyTrend: [TrendPoint]
    public var asOfPT: Date?
    public var confidence: MetricConfidence

    public static let empty = SubscriptionHealthSnapshot(
        activeSubscriptions: 0,
        billingRetry: 0,
        gracePeriod: 0,
        subscribersRaw: 0,
        activeByCountry: [],
        activeByDevice: [],
        retryRate: 0,
        graceRate: 0,
        dailyTrend: [],
        asOfPT: nil,
        confidence: .low
    )
}

public struct FinanceReconcileSnapshot: Codable, Sendable {
    public var recognizedUSD: Double
    public var financeRows: Int
    public var salesRows: Int
    public var currencies: [CurrencyAmount]
    public var monthlyDiffUSD: Double
    public var asOfPT: Date?
    public var confidence: MetricConfidence

    public static let empty = FinanceReconcileSnapshot(
        recognizedUSD: 0,
        financeRows: 0,
        salesRows: 0,
        currencies: [],
        monthlyDiffUSD: 0,
        asOfPT: nil,
        confidence: .low
    )
}

public struct DashboardModuleSnapshot: Codable, Sendable {
    public var overview: ExecutiveOverviewSnapshot
    public var growth: GrowthSnapshot
    public var subscription: SubscriptionHealthSnapshot
    public var finance: FinanceReconcileSnapshot
    public var dataHealth: DataHealthSnapshot
    public var generatedAt: Date

    public static let empty = DashboardModuleSnapshot(
        overview: .empty,
        growth: .empty,
        subscription: .empty,
        finance: .empty,
        dataHealth: .empty,
        generatedAt: Date()
    )
}

public struct ReviewsSummarySnapshot: Codable, Sendable {
    public var total: Int
    public var averageRating: Double
    public var histogram: [Int: Int]
    public var byTerritory: [BreakdownEntry]
    public var unresolvedResponses: Int
    public var latestDate: Date?

    public init(
        total: Int,
        averageRating: Double,
        histogram: [Int: Int],
        byTerritory: [BreakdownEntry],
        unresolvedResponses: Int,
        latestDate: Date?
    ) {
        self.total = total
        self.averageRating = averageRating
        self.histogram = histogram
        self.byTerritory = byTerritory
        self.unresolvedResponses = unresolvedResponses
        self.latestDate = latestDate
    }
}
