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
import ACDAnalytics
import ArgumentParser

extension QueryCompareMode: ExpressibleByArgument {}
extension QueryGroupBy: ExpressibleByArgument {}

struct GlobalOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output format: json, table, markdown.")
    var output: OutputFormat = .json
}

struct CredentialsOptions: ParsableArguments {
    @Option(help: "ASC issuer ID.")
    var issuerID: String?

    @Option(help: "ASC key ID.")
    var keyID: String?

    @Option(help: "ASC vendor number.")
    var vendorNumber: String?

    @Option(help: "Path to AuthKey_XXXX.p8.")
    var p8Path: String?

    var overrides: CredentialsOverrides {
        CredentialsOverrides(
            issuerID: issuerID,
            keyID: keyID,
            vendorNumber: vendorNumber,
            p8Path: p8Path
        )
    }
}

struct TimeSelectionOptions: ParsableArguments {
    @Option(help: "Single PT date, YYYY-MM-DD.")
    var date: String?

    @Option(name: .customLong("from"), help: "PT start date, YYYY-MM-DD.")
    var from: String?

    @Option(name: .customLong("to"), help: "PT end date, YYYY-MM-DD.")
    var to: String?

    @Option(help: "Preset like last-day, last-week, last-7d, last-30d, last-month, year-to-date.")
    var range: String?

    @Option(name: .customLong("year"), help: "Calendar year.")
    var year: Int?

    @Option(name: .customLong("fiscal-month"), help: "Fiscal month, YYYY-MM.")
    var fiscalMonth: String?

    @Option(name: .customLong("fiscal-year"), help: "Fiscal year.")
    var fiscalYear: Int?

    func selection(defaultPreset: PTDateRangePreset? = nil) throws -> QueryTimeSelection {
        let selectors = [
            date?.isEmpty == false,
            from?.isEmpty == false || to?.isEmpty == false,
            range?.isEmpty == false,
            year != nil,
            fiscalMonth?.isEmpty == false,
            fiscalYear != nil
        ].filter { $0 }.count

        if selectors > 1 {
            throw PTDateWindowError.conflictingSelectors
        }

        if let date = nonEmpty(date) {
            return QueryTimeSelection(datePT: date)
        }
        if let from = nonEmpty(from), let to = nonEmpty(to) {
            return QueryTimeSelection(startDatePT: from, endDatePT: to)
        }
        if let from = nonEmpty(from) {
            return QueryTimeSelection(startDatePT: from, endDatePT: from)
        }
        if let to = nonEmpty(to) {
            return QueryTimeSelection(startDatePT: to, endDatePT: to)
        }
        if let range = nonEmpty(range) {
            return QueryTimeSelection(rangePreset: range)
        }
        if let year {
            return QueryTimeSelection(year: year)
        }
        if let fiscalMonth = nonEmpty(fiscalMonth) {
            return QueryTimeSelection(fiscalMonth: fiscalMonth)
        }
        if let fiscalYear {
            return QueryTimeSelection(fiscalYear: fiscalYear)
        }
        if let defaultPreset {
            return QueryTimeSelection(rangePreset: defaultPreset.rawValue)
        }
        return QueryTimeSelection()
    }
}

struct CompareOptions: ParsableArguments {
    @Option(help: "Compare mode: previous-period, week-over-week, month-over-month, year-over-year, custom.")
    var compare: QueryCompareMode?

    @Option(name: .customLong("compare-from"), help: "Custom compare start date, YYYY-MM-DD.")
    var compareFrom: String?

    @Option(name: .customLong("compare-to"), help: "Custom compare end date, YYYY-MM-DD.")
    var compareTo: String?

    func mode() throws -> QueryCompareMode? {
        guard compare != nil || compareFrom != nil || compareTo != nil else { return nil }
        if compareFrom != nil || compareTo != nil {
            if let compare, compare != .custom {
                throw ValidationError("Custom compare dates require --compare custom.")
            }
            return .custom
        }
        return compare ?? .previousPeriod
    }

    func customSelection() -> QueryTimeSelection? {
        guard compareFrom != nil || compareTo != nil else { return nil }
        let from = nonEmpty(compareFrom) ?? nonEmpty(compareTo)
        let to = nonEmpty(compareTo) ?? nonEmpty(compareFrom)
        return QueryTimeSelection(startDatePT: from, endDatePT: to)
    }
}

struct FilterOptions: ParsableArguments {
    @Option(name: .customLong("app"), help: "App filter. Repeat for multiple values.")
    var app: [String] = []

    @Option(name: .customLong("version"), help: "Version filter. Repeat for multiple values.")
    var version: [String] = []

    @Option(name: .customLong("territory"), help: "Territory filter. Repeat for multiple values.")
    var territory: [String] = []

    @Option(name: .customLong("device"), help: "Device filter. Repeat for multiple values.")
    var device: [String] = []

    @Option(name: .customLong("sku"), help: "SKU filter. Repeat for multiple values.")
    var sku: [String] = []

    @Option(name: .customLong("subscription"), help: "Subscription filter. Repeat for multiple values.")
    var subscription: [String] = []

    @Option(name: .customLong("platform"), help: "Platform filter. Repeat for multiple values.")
    var platform: [String] = []

    @Option(name: .customLong("source-report"), help: "Source report filter. Repeat for multiple values.")
    var sourceReport: [String] = []

    @Option(name: .customLong("rating"), help: "Rating filter. Repeat for multiple values.")
    var rating: [Int] = []

    @Option(name: .customLong("response-state"), help: "Response state filter.")
    var responseState: String?

    @Option(help: "Result limit.")
    var limit: Int?

    func queryFilters() -> QueryFilterSet {
        QueryFilterSet(
            app: app,
            version: version,
            territory: territory,
            device: device,
            sku: sku,
            subscription: subscription,
            platform: platform,
            sourceReport: sourceReport,
            rating: rating,
            responseState: responseState
        )
    }
}

struct FetchControlOptions: ParsableArguments {
    @Flag(help: "Read local cache only.")
    var offline = false

    @Flag(help: "Refresh cached data when credentials are available.")
    var refresh = false
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func makeRuntime(
    credentials: CredentialsOptions,
    offline: Bool = false,
    requireCredentials: Bool = false
) throws -> RuntimeContext {
    if requireCredentials {
        return try RuntimeFactory.make(overrides: credentials.overrides, credentialsMode: .required)
    }
    return try RuntimeFactory.make(
        overrides: credentials.overrides,
        credentialsMode: offline ? .disabled : .optional
    )
}

private func makeSpec(
    dataset: QueryDataset,
    operation: QueryOperation,
    time: TimeSelectionOptions,
    filters: FilterOptions,
    compare: CompareOptions,
    groupBy: [QueryGroupBy],
    defaultPreset: PTDateRangePreset
) throws -> DataQuerySpec {
    DataQuerySpec(
        dataset: dataset,
        operation: operation,
        time: try time.selection(defaultPreset: defaultPreset),
        compare: try compare.mode(),
        compareTime: compare.customSelection(),
        filters: filters.queryFilters(),
        groupBy: groupBy,
        limit: filters.limit
    )
}

@main
@available(macOS 10.15, *)
struct ACDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-connect-data-cli",
        abstract: "Direct App Store Connect data queries for official Apple reporting APIs.",
        subcommands: [Auth.self, Capabilities.self, Sales.self, Reviews.self, Finance.self, Analytics.self, Brief.self, Query.self, Cache.self]
    )
}

extension ACDCommand {
    struct Auth: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Validate.self])

        struct Validate: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                try await runtime.client?.validateToken()
                try OutputRenderer.write(
                    [
                        "status": "ok",
                        "issuerID": runtime.credentials?.maskedIssuerID ?? "",
                        "keyID": runtime.credentials?.maskedKeyID ?? "",
                        "vendorNumber": runtime.credentials?.maskedVendorNumber ?? ""
                    ],
                    format: global.output
                )
            }
        }
    }

    struct Capabilities: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [List.self])

        struct List: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials)
                try OutputRenderer.write(runtime.analytics.capabilities(), format: global.output)
            }
        }
    }

    struct Sales: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Records.self, Aggregate.self, Compare.self])
    }

    struct Reviews: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Records.self, Aggregate.self, Compare.self])
    }

    struct Finance: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Records.self, Aggregate.self, Compare.self])
    }

    struct Analytics: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Records.self, Aggregate.self, Compare.self])
    }

    struct Brief: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Weekly.self, Monthly.self])
    }

    struct Query: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Run.self])

        struct Run: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var fetch: FetchControlOptions
            @Option(name: .long, help: "Path to JSON spec or - for stdin.")
            var spec: String

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                let inputData: Data
                if spec == "-" {
                    inputData = FileHandle.standardInput.readDataToEndOfFile()
                } else {
                    inputData = try Data(contentsOf: URL(fileURLWithPath: spec))
                }
                let querySpec = try JSONDecoder().decode(DataQuerySpec.self, from: inputData)
                let result = try await runtime.analytics.execute(spec: querySpec, offline: fetch.offline, refresh: fetch.refresh)
                try OutputRenderer.write(result, format: global.output)
            }
        }
    }

    struct Cache: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Clear.self])

        struct Clear: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials)
                try runtime.cacheStore.clear()
                try OutputRenderer.write(
                    ["status": "cleared", "path": runtime.paths.cacheRoot.path],
                    format: global.output
                )
            }
        }
    }
}

private protocol DatasetCommand {
    static var dataset: QueryDataset { get }
    static var defaultPreset: PTDateRangePreset { get }
}

private extension DatasetCommand where Self: AsyncParsableCommand {
    func executeDataset(
        operation: QueryOperation,
        global: GlobalOptions,
        credentials: CredentialsOptions,
        time: TimeSelectionOptions,
        filters: FilterOptions,
        compare: CompareOptions,
        groupBy: [QueryGroupBy],
        fetch: FetchControlOptions
    ) async throws {
        let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
        let spec = try makeSpec(
            dataset: Self.dataset,
            operation: operation,
            time: time,
            filters: filters,
            compare: compare,
            groupBy: groupBy,
            defaultPreset: Self.defaultPreset
        )
        let result = try await runtime.analytics.execute(spec: spec, offline: fetch.offline, refresh: fetch.refresh)
        try OutputRenderer.write(result, format: global.output)
    }
}

extension ACDCommand.Sales {
    struct Records: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .sales
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: CompareOptions(), groupBy: [], fetch: fetch)
        }
    }

    struct Aggregate: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .sales
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .aggregate, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }

    struct Compare: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .sales
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .compare, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }
}

extension ACDCommand.Reviews {
    struct Records: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .reviews
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: CompareOptions(), groupBy: [], fetch: fetch)
        }
    }

    struct Aggregate: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .reviews
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .aggregate, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }

    struct Compare: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .reviews
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .compare, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }
}

extension ACDCommand.Finance {
    struct Records: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .finance
        static let defaultPreset: PTDateRangePreset = .lastMonth
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: CompareOptions(), groupBy: [], fetch: fetch)
        }
    }

    struct Aggregate: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .finance
        static let defaultPreset: PTDateRangePreset = .lastMonth
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .aggregate, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }

    struct Compare: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .finance
        static let defaultPreset: PTDateRangePreset = .lastMonth
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .compare, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }
}

extension ACDCommand.Analytics {
    struct Records: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .analytics
        static let defaultPreset: PTDateRangePreset = .last7d
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: CompareOptions(), groupBy: [], fetch: fetch)
        }
    }

    struct Aggregate: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .analytics
        static let defaultPreset: PTDateRangePreset = .lastWeek
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .aggregate, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }

    struct Compare: AsyncParsableCommand, DatasetCommand {
        static let dataset: QueryDataset = .analytics
        static let defaultPreset: PTDateRangePreset = .lastWeek
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var time: TimeSelectionOptions
        @OptionGroup var filters: FilterOptions
        @OptionGroup var compare: CompareOptions
        @Option(name: .customLong("group-by"), help: "Group by field. Repeat for multiple values.")
        var groupBy: [QueryGroupBy] = []
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeDataset(operation: .compare, global: global, credentials: credentials, time: time, filters: filters, compare: compare, groupBy: groupBy, fetch: fetch)
        }
    }
}

extension ACDCommand.Brief {
    struct Weekly: AsyncParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
            let spec = DataQuerySpec(
                dataset: .brief,
                operation: .brief,
                time: QueryTimeSelection(rangePreset: PTDateRangePreset.lastWeek.rawValue),
                compare: .weekOverWeek
            )
            let result = try await runtime.analytics.execute(spec: spec, offline: fetch.offline, refresh: fetch.refresh)
            try OutputRenderer.write(result, format: global.output)
        }
    }

    struct Monthly: AsyncParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
            let spec = DataQuerySpec(
                dataset: .brief,
                operation: .brief,
                time: QueryTimeSelection(rangePreset: PTDateRangePreset.lastMonth.rawValue),
                compare: .monthOverMonth
            )
            let result = try await runtime.analytics.execute(spec: spec, offline: fetch.offline, refresh: fetch.refresh)
            try OutputRenderer.write(result, format: global.output)
        }
    }
}
