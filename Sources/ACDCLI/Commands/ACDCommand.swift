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

struct BriefGlobalOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Output format: json, table, markdown.")
    var output: OutputFormat = .table
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
    @Option(help: "Single Apple business date in PT, YYYY-MM-DD.")
    var date: String?

    @Option(name: .customLong("from"), help: "PT start date, YYYY-MM-DD.")
    var from: String?

    @Option(name: .customLong("to"), help: "PT end date, YYYY-MM-DD.")
    var to: String?

    @Option(help: "Preset like last-day, this-week, this-month, last-7d, last-30d, last-month, year-to-date.")
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

    @Option(name: .customLong("currency"), help: "Currency filter. Repeat for multiple values.")
    var currency: [String] = []

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
            currency: currency,
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

struct ConfigScopeOptions: ParsableArguments {
    @Flag(name: .long, help: "Use ./.app-connect-data-cli/config.json instead of ~/.app-connect-data-cli/config.json.")
    var local = false
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizeReportingCurrency(_ value: String) throws -> String {
    let normalized = value.normalizedCurrencyCode
    let isThreeLetterCode = normalized.count == 3 && normalized.unicodeScalars.allSatisfy(CharacterSet.uppercaseLetters.contains)
    guard normalized.isUnknownCurrencyCode == false, isThreeLetterCode else {
        throw ValidationError("Reporting currency must be a 3-letter ISO code, for example USD or CNY.")
    }
    return normalized
}

private func normalizeTimeZoneIdentifier(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false, let timeZone = TimeZone(identifier: trimmed) else {
        throw ValidationError("Display time zone must be an IANA identifier, for example Asia/Shanghai or America/Los_Angeles.")
    }
    return timeZone.identifier
}

private func configURL(paths: RuntimePaths, local: Bool) -> URL {
    (local ? paths.localBase : paths.userBase).appendingPathComponent("config.json")
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
    compare: CompareOptions?,
    groupBy: [QueryGroupBy],
    defaultPreset: PTDateRangePreset
) throws -> DataQuerySpec {
    DataQuerySpec(
        dataset: dataset,
        operation: operation,
        time: try time.selection(defaultPreset: defaultPreset),
        compare: try compare?.mode(),
        compareTime: compare?.customSelection(),
        filters: filters.queryFilters(),
        groupBy: groupBy,
        limit: filters.limit
    )
}

private func executeBriefSummary(
    period: BriefSummaryPeriod,
    output: OutputFormat,
    credentials: CredentialsOptions,
    fetch: FetchControlOptions
) async throws {
    let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
    let report = try await BriefSummaryBuilder(runtime: runtime, offline: fetch.offline, refresh: fetch.refresh)
        .build(period: period)
    try OutputRenderer.write(report, format: output)
}

@main
@available(macOS 10.15, *)
struct ACDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adc",
        abstract: "Direct App Store Connect data queries for official Apple reporting APIs.",
        discussion: """
        Start here:
          adc overview daily
          adc overview weekly
          adc sales aggregate --range last-7d --group-by territory
          adc query run --spec -
        """,
        subcommands: [Auth.self, Config.self, Capabilities.self, Overview.self, Sales.self, Reviews.self, Finance.self, Analytics.self, Brief.self, Query.self, Cache.self]
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

    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage local defaults such as reporting currency and display time zone.",
            subcommands: [Currency.self, Timezone.self]
        )

        struct Currency: AsyncParsableCommand {
            static let configuration = CommandConfiguration(subcommands: [Show.self, Set.self])

            struct Show: AsyncParsableCommand {
                @OptionGroup var global: GlobalOptions
                @OptionGroup var scope: ConfigScopeOptions

                mutating func run() async throws {
                    let runtime = try RuntimeFactory.make(credentialsMode: .disabled)
                    let targetURL = configURL(paths: runtime.paths, local: scope.local)
                    let storedConfig = try RuntimeFactory.loadConfig(at: targetURL)
                    let reportingCurrency = scope.local
                        ? (storedConfig?.reportingCurrency ?? "")
                        : (runtime.config.reportingCurrency ?? "USD")
                    try OutputRenderer.write(
                        [
                            "scope": scope.local ? "local" : "effective",
                            "reportingCurrency": reportingCurrency,
                            "path": scope.local ? targetURL.path : ""
                        ],
                        format: global.output
                    )
                }
            }

            struct Set: AsyncParsableCommand {
                @OptionGroup var global: GlobalOptions
                @OptionGroup var scope: ConfigScopeOptions
                @Argument(help: "3-letter ISO currency code, for example USD or CNY.")
                var code: String

                mutating func run() async throws {
                    let runtime = try RuntimeFactory.make(credentialsMode: .disabled)
                    let targetURL = configURL(paths: runtime.paths, local: scope.local)
                    var config = try RuntimeFactory.loadConfig(at: targetURL) ?? ACDConfig()
                    config.reportingCurrency = try normalizeReportingCurrency(code)
                    try RuntimeFactory.saveConfig(config, at: targetURL)
                    try OutputRenderer.write(
                        [
                            "status": "ok",
                            "scope": scope.local ? "local" : "user",
                            "reportingCurrency": config.reportingCurrency ?? "USD",
                            "path": targetURL.path
                        ],
                        format: global.output
                    )
                }
            }
        }

        struct Timezone: AsyncParsableCommand {
            static let configuration = CommandConfiguration(subcommands: [Show.self, Set.self])

            struct Show: AsyncParsableCommand {
                @OptionGroup var global: GlobalOptions
                @OptionGroup var scope: ConfigScopeOptions

                mutating func run() async throws {
                    let runtime = try RuntimeFactory.make(credentialsMode: .disabled)
                    let targetURL = configURL(paths: runtime.paths, local: scope.local)
                    let storedConfig = try RuntimeFactory.loadConfig(at: targetURL)
                    let displayTimeZone = scope.local
                        ? (storedConfig?.displayTimeZone ?? "")
                        : (runtime.config.displayTimeZone ?? TimeZone.autoupdatingCurrent.identifier)
                    try OutputRenderer.write(
                        [
                            "scope": scope.local ? "local" : "effective",
                            "displayTimeZone": displayTimeZone,
                            "path": scope.local ? targetURL.path : ""
                        ],
                        format: global.output
                    )
                }
            }

            struct Set: AsyncParsableCommand {
                @OptionGroup var global: GlobalOptions
                @OptionGroup var scope: ConfigScopeOptions
                @Argument(help: "IANA time zone identifier, for example Asia/Shanghai.")
                var identifier: String

                mutating func run() async throws {
                    let runtime = try RuntimeFactory.make(credentialsMode: .disabled)
                    let targetURL = configURL(paths: runtime.paths, local: scope.local)
                    var config = try RuntimeFactory.loadConfig(at: targetURL) ?? ACDConfig()
                    config.displayTimeZone = try normalizeTimeZoneIdentifier(identifier)
                    try RuntimeFactory.saveConfig(config, at: targetURL)
                    try OutputRenderer.write(
                        [
                            "status": "ok",
                            "scope": scope.local ? "local" : "user",
                            "displayTimeZone": config.displayTimeZone ?? TimeZone.autoupdatingCurrent.identifier,
                            "path": targetURL.path
                        ],
                        format: global.output
                    )
                }
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
        static let configuration = CommandConfiguration(
            abstract: "Multi-table business summaries for humans.",
            discussion: """
            Semantics:
              daily      latest complete Apple business day
              weekly     this week to date
              monthly    this month to date
              last-7d    last 7 complete days
              last-30d   last 30 complete days
              last-month previous full month
            """,
            subcommands: [Daily.self, Weekly.self, Monthly.self, Last7d.self, Last30d.self, LastMonth.self]
        )
    }

    struct Overview: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Friendly alias for brief summaries.",
            discussion: """
            Same output as `adc brief`, but named for humans.
            """,
            subcommands: [
                ACDCommand.Brief.Daily.self,
                ACDCommand.Brief.Weekly.self,
                ACDCommand.Brief.Monthly.self,
                ACDCommand.Brief.Last7d.self,
                ACDCommand.Brief.Last30d.self,
                ACDCommand.Brief.LastMonth.self
            ]
        )
    }

    struct Query: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run machine-readable JSON specs.",
            subcommands: [Run.self]
        )

        struct Run: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Execute a JSON query spec. Brief specs return BriefSummaryReport. Other datasets return QueryResult."
            )
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
                if querySpec.dataset == .brief {
                    let report = try await BriefSummaryBuilder(runtime: runtime, offline: fetch.offline, refresh: fetch.refresh)
                        .build(spec: querySpec)
                    try OutputRenderer.write(report, format: global.output)
                    return
                }
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
        compare: CompareOptions?,
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
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: nil, groupBy: [], fetch: fetch)
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
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: nil, groupBy: [], fetch: fetch)
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
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: nil, groupBy: [], fetch: fetch)
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
            try await executeDataset(operation: .records, global: global, credentials: credentials, time: time, filters: filters, compare: nil, groupBy: [], fetch: fetch)
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
    struct Daily: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Latest complete Apple business day versus the previous complete day.")
        @OptionGroup var global: BriefGlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeBriefSummary(period: .daily, output: global.output, credentials: credentials, fetch: fetch)
        }
    }

    struct Weekly: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "This week to date versus the previous week at the same progress point.")
        @OptionGroup var global: BriefGlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeBriefSummary(period: .weekly, output: global.output, credentials: credentials, fetch: fetch)
        }
    }

    struct Monthly: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "This month to date versus the previous month at the same progress point.")
        @OptionGroup var global: BriefGlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeBriefSummary(period: .monthly, output: global.output, credentials: credentials, fetch: fetch)
        }
    }

    struct Last7d: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "last-7d", abstract: "Last 7 complete days versus the 7 days before that.")
        @OptionGroup var global: BriefGlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeBriefSummary(period: .last7d, output: global.output, credentials: credentials, fetch: fetch)
        }
    }

    struct Last30d: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "last-30d", abstract: "Last 30 complete days versus the 30 days before that.")
        @OptionGroup var global: BriefGlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeBriefSummary(period: .last30d, output: global.output, credentials: credentials, fetch: fetch)
        }
    }

    struct LastMonth: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "last-month", abstract: "Previous full month versus the month before last.")
        @OptionGroup var global: BriefGlobalOptions
        @OptionGroup var credentials: CredentialsOptions
        @OptionGroup var fetch: FetchControlOptions

        mutating func run() async throws {
            try await executeBriefSummary(period: .lastMonth, output: global.output, credentials: credentials, fetch: fetch)
        }
    }
}
