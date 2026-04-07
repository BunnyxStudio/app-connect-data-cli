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

public enum QueryDataset: String, Codable, CaseIterable, Sendable {
    case sales
    case reviews
    case finance
    case analytics
    case brief
}

public enum QueryOperation: String, Codable, CaseIterable, Sendable {
    case records
    case aggregate
    case compare
    case brief
}

public enum QueryCompareMode: String, Codable, CaseIterable, Sendable {
    case previousPeriod = "previous-period"
    case weekOverWeek = "week-over-week"
    case monthOverMonth = "month-over-month"
    case yearOverYear = "year-over-year"
    case custom
}

public enum QueryGroupBy: String, Codable, CaseIterable, Sendable {
    case day
    case week
    case month
    case fiscalMonth
    case app
    case version
    case territory
    case currency
    case device
    case sku
    case rating
    case responseState
    case reportType
    case platform
    case sourceReport
    case subscription
}

public struct QueryTimeSelection: Codable, Equatable, Sendable {
    public var datePT: String?
    public var startDatePT: String?
    public var endDatePT: String?
    public var rangePreset: String?
    public var year: Int?
    public var fiscalMonth: String?
    public var fiscalYear: Int?

    public init(
        datePT: String? = nil,
        startDatePT: String? = nil,
        endDatePT: String? = nil,
        rangePreset: String? = nil,
        year: Int? = nil,
        fiscalMonth: String? = nil,
        fiscalYear: Int? = nil
    ) {
        self.datePT = datePT
        self.startDatePT = startDatePT
        self.endDatePT = endDatePT
        self.rangePreset = rangePreset
        self.year = year
        self.fiscalMonth = fiscalMonth
        self.fiscalYear = fiscalYear
    }

    private enum CodingKeys: String, CodingKey {
        case datePT
        case startDatePT
        case endDatePT
        case rangePreset
        case year
        case fiscalMonth
        case fiscalYear
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            datePT: try container.decodeIfPresent(String.self, forKey: .datePT),
            startDatePT: try container.decodeIfPresent(String.self, forKey: .startDatePT),
            endDatePT: try container.decodeIfPresent(String.self, forKey: .endDatePT),
            rangePreset: try container.decodeIfPresent(String.self, forKey: .rangePreset),
            year: try container.decodeIfPresent(Int.self, forKey: .year),
            fiscalMonth: try container.decodeIfPresent(String.self, forKey: .fiscalMonth),
            fiscalYear: try container.decodeIfPresent(Int.self, forKey: .fiscalYear)
        )
    }
}

public struct QueryFilterSet: Codable, Equatable, Sendable {
    public var app: [String]
    public var version: [String]
    public var territory: [String]
    public var device: [String]
    public var sku: [String]
    public var subscription: [String]
    public var platform: [String]
    public var sourceReport: [String]
    public var rating: [Int]
    public var responseState: String?

    public init(
        app: [String] = [],
        version: [String] = [],
        territory: [String] = [],
        device: [String] = [],
        sku: [String] = [],
        subscription: [String] = [],
        platform: [String] = [],
        sourceReport: [String] = [],
        rating: [Int] = [],
        responseState: String? = nil
    ) {
        self.app = app
        self.version = version
        self.territory = territory
        self.device = device
        self.sku = sku
        self.subscription = subscription
        self.platform = platform
        self.sourceReport = sourceReport
        self.rating = rating
        self.responseState = responseState
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case version
        case territory
        case device
        case sku
        case subscription
        case platform
        case sourceReport
        case rating
        case responseState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            app: try container.decodeIfPresent([String].self, forKey: .app) ?? [],
            version: try container.decodeIfPresent([String].self, forKey: .version) ?? [],
            territory: try container.decodeIfPresent([String].self, forKey: .territory) ?? [],
            device: try container.decodeIfPresent([String].self, forKey: .device) ?? [],
            sku: try container.decodeIfPresent([String].self, forKey: .sku) ?? [],
            subscription: try container.decodeIfPresent([String].self, forKey: .subscription) ?? [],
            platform: try container.decodeIfPresent([String].self, forKey: .platform) ?? [],
            sourceReport: try container.decodeIfPresent([String].self, forKey: .sourceReport) ?? [],
            rating: try container.decodeIfPresent([Int].self, forKey: .rating) ?? [],
            responseState: try container.decodeIfPresent(String.self, forKey: .responseState)
        )
    }
}

public struct DataQuerySpec: Codable, Equatable, Sendable {
    public var dataset: QueryDataset
    public var operation: QueryOperation
    public var time: QueryTimeSelection
    public var compare: QueryCompareMode?
    public var compareTime: QueryTimeSelection?
    public var filters: QueryFilterSet
    public var groupBy: [QueryGroupBy]
    public var limit: Int?

    public init(
        dataset: QueryDataset,
        operation: QueryOperation,
        time: QueryTimeSelection = QueryTimeSelection(),
        compare: QueryCompareMode? = nil,
        compareTime: QueryTimeSelection? = nil,
        filters: QueryFilterSet = QueryFilterSet(),
        groupBy: [QueryGroupBy] = [],
        limit: Int? = nil
    ) {
        self.dataset = dataset
        self.operation = operation
        self.time = time
        self.compare = compare
        self.compareTime = compareTime
        self.filters = filters
        self.groupBy = groupBy
        self.limit = limit
    }

    private enum CodingKeys: String, CodingKey {
        case dataset
        case operation
        case time
        case compare
        case compareTime
        case filters
        case groupBy
        case limit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dataset: try container.decode(QueryDataset.self, forKey: .dataset),
            operation: try container.decode(QueryOperation.self, forKey: .operation),
            time: try container.decodeIfPresent(QueryTimeSelection.self, forKey: .time) ?? QueryTimeSelection(),
            compare: try container.decodeIfPresent(QueryCompareMode.self, forKey: .compare),
            compareTime: try container.decodeIfPresent(QueryTimeSelection.self, forKey: .compareTime),
            filters: try container.decodeIfPresent(QueryFilterSet.self, forKey: .filters) ?? QueryFilterSet(),
            groupBy: try container.decodeIfPresent([QueryGroupBy].self, forKey: .groupBy) ?? [],
            limit: try container.decodeIfPresent(Int.self, forKey: .limit)
        )
    }
}

public struct QueryWarning: Codable, Equatable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct TableModel: Codable, Equatable, Sendable {
    public var title: String?
    public var columns: [String]
    public var rows: [[String]]

    public init(title: String? = nil, columns: [String], rows: [[String]]) {
        self.title = title
        self.columns = columns
        self.rows = rows
    }
}

public struct QueryRecord: Codable, Equatable, Sendable {
    public var id: String
    public var dimensions: [String: String]
    public var metrics: [String: Double]

    public init(id: String, dimensions: [String: String], metrics: [String: Double]) {
        self.id = id
        self.dimensions = dimensions
        self.metrics = metrics
    }
}

public struct QueryAggregateRow: Codable, Equatable, Sendable {
    public var group: [String: String]
    public var metrics: [String: Double]

    public init(group: [String: String], metrics: [String: Double]) {
        self.group = group
        self.metrics = metrics
    }
}

public struct QueryComparisonValue: Codable, Equatable, Sendable {
    public var current: Double
    public var previous: Double
    public var delta: Double
    public var deltaPercent: Double?

    public init(current: Double, previous: Double) {
        self.current = current
        self.previous = previous
        self.delta = current - previous
        if previous == 0 {
            self.deltaPercent = current == 0 ? 0 : nil
        } else {
            self.deltaPercent = (current - previous) / previous
        }
    }
}

public struct QueryComparisonRow: Codable, Equatable, Sendable {
    public var group: [String: String]
    public var metrics: [String: QueryComparisonValue]

    public init(group: [String: String], metrics: [String: QueryComparisonValue]) {
        self.group = group
        self.metrics = metrics
    }
}

public struct BriefRow: Codable, Equatable, Sendable {
    public var metric: String
    public var current: String
    public var compare: String?
    public var change: String?
    public var note: String?

    public init(
        metric: String,
        current: String,
        compare: String? = nil,
        change: String? = nil,
        note: String? = nil
    ) {
        self.metric = metric
        self.current = current
        self.compare = compare
        self.change = change
        self.note = note
    }
}

public struct QueryResultData: Codable, Equatable, Sendable {
    public var records: [QueryRecord]
    public var aggregates: [QueryAggregateRow]
    public var comparisons: [QueryComparisonRow]
    public var brief: [BriefRow]

    public init(
        records: [QueryRecord] = [],
        aggregates: [QueryAggregateRow] = [],
        comparisons: [QueryComparisonRow] = [],
        brief: [BriefRow] = []
    ) {
        self.records = records
        self.aggregates = aggregates
        self.comparisons = comparisons
        self.brief = brief
    }
}

public struct QueryTimeEnvelope: Codable, Equatable, Sendable {
    public var label: String
    public var datePT: String?
    public var startDatePT: String?
    public var endDatePT: String?
    public var year: Int?
    public var fiscalMonth: String?
    public var fiscalYear: Int?

    public init(
        label: String,
        datePT: String? = nil,
        startDatePT: String? = nil,
        endDatePT: String? = nil,
        year: Int? = nil,
        fiscalMonth: String? = nil,
        fiscalYear: Int? = nil
    ) {
        self.label = label
        self.datePT = datePT
        self.startDatePT = startDatePT
        self.endDatePT = endDatePT
        self.year = year
        self.fiscalMonth = fiscalMonth
        self.fiscalYear = fiscalYear
    }
}

public struct QueryComparisonEnvelope: Codable, Equatable, Sendable {
    public var mode: QueryCompareMode
    public var current: QueryTimeEnvelope
    public var previous: QueryTimeEnvelope

    public init(mode: QueryCompareMode, current: QueryTimeEnvelope, previous: QueryTimeEnvelope) {
        self.mode = mode
        self.current = current
        self.previous = previous
    }
}

public struct QueryResult: Codable, Equatable, Sendable {
    public var dataset: QueryDataset
    public var operation: QueryOperation
    public var time: QueryTimeEnvelope
    public var filters: QueryFilterSet
    public var source: [String]
    public var data: QueryResultData
    public var comparison: QueryComparisonEnvelope?
    public var warnings: [QueryWarning]
    public var tableModel: TableModel?

    public init(
        dataset: QueryDataset,
        operation: QueryOperation,
        time: QueryTimeEnvelope,
        filters: QueryFilterSet,
        source: [String],
        data: QueryResultData,
        comparison: QueryComparisonEnvelope? = nil,
        warnings: [QueryWarning] = [],
        tableModel: TableModel? = nil
    ) {
        self.dataset = dataset
        self.operation = operation
        self.time = time
        self.filters = filters
        self.source = source
        self.data = data
        self.comparison = comparison
        self.warnings = warnings
        self.tableModel = tableModel
    }
}

public struct CapabilityDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var status: String
    public var whatYouCanQuery: [String]
    public var whatYouCannotQuery: [String]
    public var timeSupport: [String]
    public var filterSupport: [String]
    public var notes: [String]

    public init(
        name: String,
        status: String,
        whatYouCanQuery: [String],
        whatYouCannotQuery: [String],
        timeSupport: [String],
        filterSupport: [String],
        notes: [String]
    ) {
        self.name = name
        self.status = status
        self.whatYouCanQuery = whatYouCanQuery
        self.whatYouCannotQuery = whatYouCannotQuery
        self.timeSupport = timeSupport
        self.filterSupport = filterSupport
        self.notes = notes
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
