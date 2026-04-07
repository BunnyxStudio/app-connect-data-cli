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

public struct QueryFilters: Codable, Equatable, Sendable {
    public var datePT: String?
    public var startDatePT: String?
    public var endDatePT: String?
    public var rangePreset: String?
    public var territory: String?
    public var device: String?
    public var limit: Int?

    public init(
        datePT: String? = nil,
        startDatePT: String? = nil,
        endDatePT: String? = nil,
        rangePreset: String? = nil,
        territory: String? = nil,
        device: String? = nil,
        limit: Int? = nil
    ) {
        self.datePT = datePT
        self.startDatePT = startDatePT
        self.endDatePT = endDatePT
        self.rangePreset = rangePreset
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
