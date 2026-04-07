import Foundation

public struct QueryFilters: Codable, Equatable, Sendable {
    public var startDatePT: String?
    public var endDatePT: String?
    public var territory: String?
    public var device: String?
    public var limit: Int?

    public init(
        startDatePT: String? = nil,
        endDatePT: String? = nil,
        territory: String? = nil,
        device: String? = nil,
        limit: Int? = nil
    ) {
        self.startDatePT = startDatePT
        self.endDatePT = endDatePT
        self.territory = territory
        self.device = device
        self.limit = limit
    }
}

public enum QuerySpecKind: String, Codable, Sendable {
    case snapshot
    case modules
    case health
    case trend
    case topProducts = "top-products"
    case reviewsList = "reviews.list"
    case reviewsSummary = "reviews.summary"
}

public struct QuerySpec: Codable, Sendable {
    public var kind: QuerySpecKind
    public var source: DashboardDataSource?
    public var filters: QueryFilters

    public init(
        kind: QuerySpecKind,
        source: DashboardDataSource? = nil,
        filters: QueryFilters = QueryFilters()
    ) {
        self.kind = kind
        self.source = source
        self.filters = filters
    }
}

public struct DoctorAuditSnapshot: Codable, Sendable {
    public var totalReports: Int
    public var totalReviewItems: Int
    public var unknownCurrencyRows: Int
    public var duplicateReportKeys: [String]
    public var latestSalesDatePT: String?
    public var latestFinanceMonth: String?

    public init(
        totalReports: Int,
        totalReviewItems: Int,
        unknownCurrencyRows: Int,
        duplicateReportKeys: [String],
        latestSalesDatePT: String?,
        latestFinanceMonth: String?
    ) {
        self.totalReports = totalReports
        self.totalReviewItems = totalReviewItems
        self.unknownCurrencyRows = unknownCurrencyRows
        self.duplicateReportKeys = duplicateReportKeys
        self.latestSalesDatePT = latestSalesDatePT
        self.latestFinanceMonth = latestFinanceMonth
    }
}

public struct ReconcileSnapshot: Codable, Sendable {
    public var salesUSD: Double
    public var financeUSD: Double
    public var diffUSD: Double
    public var currencies: [CurrencyAmount]

    public init(
        salesUSD: Double,
        financeUSD: Double,
        diffUSD: Double,
        currencies: [CurrencyAmount]
    ) {
        self.salesUSD = salesUSD
        self.financeUSD = financeUSD
        self.diffUSD = diffUSD
        self.currencies = currencies
    }
}
