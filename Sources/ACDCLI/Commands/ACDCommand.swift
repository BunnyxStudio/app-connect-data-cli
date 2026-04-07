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

extension DashboardDataSource: ExpressibleByArgument {}

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

struct DateSelectionOptions: ParsableArguments {
    @Option(help: "Single PT date, YYYY-MM-DD.")
    var date: String?

    @Option(name: .customLong("from"), help: "PT start date, YYYY-MM-DD.")
    var from: String?

    @Option(name: .customLong("to"), help: "PT end date, YYYY-MM-DD.")
    var to: String?

    @Option(help: "Preset like today, last-day, last-week, last-7d, last-30d, this-week, this-month, last-month.")
    var range: String?

    func normalizedFilters(
        base: QueryFilters = QueryFilters(),
        territory: String? = nil,
        device: String? = nil,
        limit: Int? = nil,
        defaultPreset: PTDateRangePreset = .last7d
    ) throws -> QueryFilters {
        try normalizeFilters(
            base: base,
            date: date,
            from: from,
            to: to,
            range: range,
            territory: territory,
            device: device,
            limit: limit,
            defaultPreset: defaultPreset
        )
    }
}

struct FetchControlOptions: ParsableArguments {
    @Flag(help: "Only read local cache. Do not call App Store Connect.")
    var offline = false

    @Flag(help: "Ignore cached report files and refresh from App Store Connect.")
    var refresh = false
}

struct ReviewFetchOptions: ParsableArguments {
    @Option(help: "Max apps to scan when reading reviews online.")
    var maxApps: Int?

    @Option(help: "Max reviews per app when reading reviews online.")
    var perAppLimit: Int?

    @Option(help: "Total review limit when reading reviews online.")
    var totalLimit: Int?
}

@main
@available(macOS 10.15, *)
struct ACDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-connect-data-cli",
        abstract: "Direct App Store Connect data queries for reports and reviews.",
        subcommands: [Auth.self, Query.self, Reviews.self, Doctor.self, Cache.self, Sync.self]
    )
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

private func normalizeFilters(
    base: QueryFilters = QueryFilters(),
    date: String? = nil,
    from: String? = nil,
    to: String? = nil,
    range: String? = nil,
    territory: String? = nil,
    device: String? = nil,
    limit: Int? = nil,
    defaultPreset: PTDateRangePreset = .last7d
) throws -> QueryFilters {
    var filters = base
    if let date {
        filters.datePT = date
    }
    if let from {
        filters.startDatePT = from
    }
    if let to {
        filters.endDatePT = to
    }
    if let range {
        filters.rangePreset = range
    }
    if let territory {
        filters.territory = territory
    }
    if let device {
        filters.device = device
    }
    if let limit {
        filters.limit = limit
    }
    if let window = try resolvePTDateWindow(
        datePT: filters.datePT,
        startDatePT: filters.startDatePT,
        endDatePT: filters.endDatePT,
        rangePreset: filters.rangePreset,
        defaultPreset: defaultPreset
    ) {
        filters.startDatePT = window.startDatePT
        filters.endDatePT = window.endDatePT
    }
    filters.datePT = nil
    filters.rangePreset = nil
    return filters
}

private func resolvedWindow(
    from filters: QueryFilters,
    defaultPreset: PTDateRangePreset = .last7d
) throws -> PTDateWindow {
    try resolvePTDateWindow(
        datePT: filters.datePT,
        startDatePT: filters.startDatePT,
        endDatePT: filters.endDatePT,
        rangePreset: filters.rangePreset,
        defaultPreset: defaultPreset
    ) ?? defaultPreset.resolve()
}

private func responseState(withResponse: Bool, withoutResponse: Bool) -> Bool? {
    if withResponse { return true }
    if withoutResponse { return false }
    return nil
}

private func preloadSourceData(
    runtime: RuntimeContext,
    source: DashboardDataSource,
    filters: QueryFilters,
    refresh: Bool
) async throws {
    guard let syncService = runtime.syncService else { return }
    let window = try resolvedWindow(from: filters)
    switch source {
    case .sales:
        _ = try await syncService.syncSales(window: window, force: refresh)
    case .finance:
        _ = try await syncService.syncFinance(
            window: window,
            regionCodes: ["ZZ", "Z1"],
            reportTypes: [.financial, .financeDetail],
            force: refresh
        )
    }
}

private func preloadModulesData(
    runtime: RuntimeContext,
    filters: QueryFilters,
    refresh: Bool
) async throws {
    guard let syncService = runtime.syncService else { return }
    let window = try resolvedWindow(from: filters)
    _ = try await syncService.syncSales(window: window, force: refresh)
    _ = try await syncService.syncSubscriptions(window: window, force: refresh)
    _ = try await syncService.syncFinance(
        window: window,
        regionCodes: ["ZZ", "Z1"],
        reportTypes: [.financial, .financeDetail],
        force: refresh
    )
}

private func preloadHealthData(
    runtime: RuntimeContext,
    refresh: Bool
) async throws {
    guard let syncService = runtime.syncService else { return }
    let recentWindow = PTDateRangePreset.last7d.resolve()
    _ = try await syncService.syncSales(window: recentWindow, force: refresh)
    _ = try await syncService.syncSubscriptions(window: recentWindow, force: refresh)
    _ = try await syncService.syncFinance(
        fiscalMonths: recentFiscalMonths(count: 2),
        regionCodes: ["ZZ", "Z1"],
        reportTypes: [.financial, .financeDetail],
        force: refresh
    )
}

private func preloadReviews(
    runtime: RuntimeContext,
    filters: QueryFilters,
    ratings: [Int],
    withResponse: Bool,
    withoutResponse: Bool,
    fetchOptions: ReviewFetchOptions,
    refresh: Bool
) async throws {
    guard let syncService = runtime.syncService else { return }
    if refresh == false, try runtime.cacheStore.loadReviews() != nil {
        return
    }
    let query = ASCCustomerReviewQuery(
        sort: .newest,
        ratings: Set(ratings),
        territory: filters.territory,
        hasPublishedResponse: responseState(withResponse: withResponse, withoutResponse: withoutResponse)
    )
    _ = try await syncService.syncReviews(
        maxApps: fetchOptions.maxApps,
        perAppLimit: fetchOptions.perAppLimit,
        totalLimit: fetchOptions.totalLimit,
        query: query
    )
}

private func filteredReviews(
    runtime: RuntimeContext,
    filters: QueryFilters,
    ratings: [Int],
    withResponse: Bool,
    withoutResponse: Bool
) throws -> [ASCLatestReview] {
    let range = try resolvePTDateWindow(
        datePT: filters.datePT,
        startDatePT: filters.startDatePT,
        endDatePT: filters.endDatePT,
        rangePreset: filters.rangePreset,
        defaultPreset: nil
    )
    let normalizedTerritory = filters.territory?.uppercased()
    let requiredResponseState = responseState(withResponse: withResponse, withoutResponse: withoutResponse)
    return try runtime.analytics.reviews().filter { review in
        let reviewDate = Calendar.pacific.startOfDay(for: review.createdDate)
        let inRange = range.map { $0.startDate <= reviewDate && reviewDate <= $0.endDate } ?? true
        let territoryMatches = normalizedTerritory.map { (review.territory ?? "").uppercased() == $0 } ?? true
        let ratingMatches = ratings.isEmpty ? true : ratings.contains(review.rating)
        let responseMatches = requiredResponseState.map { expected in
            (review.developerResponse != nil) == expected
        } ?? true
        return inRange && territoryMatches && ratingMatches && responseMatches
    }
}

private func reviewsSummary(from reviews: [ASCLatestReview]) -> ReviewsSummarySnapshot {
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
        latestDate: reviews.sorted { $0.createdDate > $1.createdDate }.first?.createdDate
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
                try OutputRenderer.write([
                    "status": "ok",
                    "issuerID": runtime.credentials?.maskedIssuerID ?? "",
                    "keyID": runtime.credentials?.maskedKeyID ?? "",
                    "vendorNumber": runtime.credentials?.maskedVendorNumber ?? ""
                ], format: global.output)
            }
        }
    }

    struct Query: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Snapshot.self, Modules.self, Health.self, Trend.self, TopProducts.self, Run.self])

        struct Snapshot: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions
            @Option(help: "sales or finance.")
            var source: DashboardDataSource = .sales
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Device filter.")
            var device: String?

            mutating func run() async throws {
                let filters = try dates.normalizedFilters(territory: territory, device: device)
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadSourceData(runtime: runtime, source: source, filters: filters, refresh: fetch.refresh)
                let payload = try await runtime.analytics.snapshot(source: source, filters: filters)
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Modules: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Device filter.")
            var device: String?

            mutating func run() async throws {
                let filters = try dates.normalizedFilters(territory: territory, device: device)
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadModulesData(runtime: runtime, filters: filters, refresh: fetch.refresh)
                let payload = try await runtime.analytics.modules(filters: filters)
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Health: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var fetch: FetchControlOptions

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadHealthData(runtime: runtime, refresh: fetch.refresh)
                let payload = try runtime.analytics.health()
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Trend: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions
            @Option(help: "sales or finance.")
            var source: DashboardDataSource = .sales

            mutating func run() async throws {
                let filters = try dates.normalizedFilters()
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadSourceData(runtime: runtime, source: source, filters: filters, refresh: fetch.refresh)
                let payload = try await runtime.analytics.trend(source: source, filters: filters)
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct TopProducts: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "top-products")

            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions
            @Option(help: "sales or finance.")
            var source: DashboardDataSource = .sales
            @Option(help: "Limit.")
            var limit: Int = 10
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Device filter.")
            var device: String?

            mutating func run() async throws {
                let filters = try dates.normalizedFilters(territory: territory, device: device, limit: limit)
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadSourceData(runtime: runtime, source: source, filters: filters, refresh: fetch.refresh)
                let payload = try await runtime.analytics.topProducts(source: source, filters: filters)
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Run: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var fetch: FetchControlOptions
            @Option(name: .long, help: "Path to JSON spec or - for stdin.")
            var spec: String

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                let data: Data
                if spec == "-" {
                    data = FileHandle.standardInput.readDataToEndOfFile()
                } else {
                    data = try Data(contentsOf: URL(fileURLWithPath: spec))
                }
                let querySpec = try JSONDecoder().decode(QuerySpec.self, from: data)
                switch querySpec.kind {
                case .snapshot:
                    let filters = try normalizeFilters(base: querySpec.filters)
                    try await preloadSourceData(runtime: runtime, source: querySpec.source ?? .sales, filters: filters, refresh: fetch.refresh)
                    let payload = try await runtime.analytics.snapshot(source: querySpec.source ?? .sales, filters: filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .modules:
                    let filters = try normalizeFilters(base: querySpec.filters)
                    try await preloadModulesData(runtime: runtime, filters: filters, refresh: fetch.refresh)
                    let payload = try await runtime.analytics.modules(filters: filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .health:
                    try await preloadHealthData(runtime: runtime, refresh: fetch.refresh)
                    let payload = try runtime.analytics.health()
                    try OutputRenderer.write(payload, format: global.output)
                case .trend:
                    let filters = try normalizeFilters(base: querySpec.filters)
                    try await preloadSourceData(runtime: runtime, source: querySpec.source ?? .sales, filters: filters, refresh: fetch.refresh)
                    let payload = try await runtime.analytics.trend(source: querySpec.source ?? .sales, filters: filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .topProducts:
                    let filters = try normalizeFilters(base: querySpec.filters)
                    try await preloadSourceData(runtime: runtime, source: querySpec.source ?? .sales, filters: filters, refresh: fetch.refresh)
                    let payload = try await runtime.analytics.topProducts(source: querySpec.source ?? .sales, filters: filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .reviewsList:
                    let filters = try normalizeFilters(base: querySpec.filters)
                    let fetchOptions = ReviewFetchOptions()
                    try await preloadReviews(
                        runtime: runtime,
                        filters: filters,
                        ratings: [],
                        withResponse: false,
                        withoutResponse: false,
                        fetchOptions: fetchOptions,
                        refresh: fetch.refresh
                    )
                    let payload = try filteredReviews(
                        runtime: runtime,
                        filters: filters,
                        ratings: [],
                        withResponse: false,
                        withoutResponse: false
                    )
                    try OutputRenderer.write(payload, format: global.output)
                case .reviewsSummary:
                    let filters = try normalizeFilters(base: querySpec.filters)
                    let fetchOptions = ReviewFetchOptions()
                    try await preloadReviews(
                        runtime: runtime,
                        filters: filters,
                        ratings: [],
                        withResponse: false,
                        withoutResponse: false,
                        fetchOptions: fetchOptions,
                        refresh: fetch.refresh
                    )
                    let payload = reviewsSummary(from: try filteredReviews(
                        runtime: runtime,
                        filters: filters,
                        ratings: [],
                        withResponse: false,
                        withoutResponse: false
                    ))
                    try OutputRenderer.write(payload, format: global.output)
                }
            }
        }
    }

    struct Reviews: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [List.self, Summary.self, Respond.self])

        struct List: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions
            @OptionGroup var fetchOptions: ReviewFetchOptions
            @Option(help: "Limit.")
            var limit: Int = 50
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Rating filter.")
            var rating: [Int] = []
            @Flag(help: "Only include reviews with developer response.")
            var withResponse = false
            @Flag(help: "Only include reviews without developer response.")
            var withoutResponse = false

            mutating func run() async throws {
                let filters = try dates.normalizedFilters(territory: territory)
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadReviews(
                    runtime: runtime,
                    filters: filters,
                    ratings: rating,
                    withResponse: withResponse,
                    withoutResponse: withoutResponse,
                    fetchOptions: fetchOptions,
                    refresh: fetch.refresh
                )
                let payload = try filteredReviews(
                    runtime: runtime,
                    filters: filters,
                    ratings: rating,
                    withResponse: withResponse,
                    withoutResponse: withoutResponse
                )
                try OutputRenderer.write(Array(payload.prefix(max(0, limit))), format: global.output)
            }
        }

        struct Summary: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions
            @OptionGroup var fetchOptions: ReviewFetchOptions
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Rating filter.")
            var rating: [Int] = []
            @Flag(help: "Only include reviews with developer response.")
            var withResponse = false
            @Flag(help: "Only include reviews without developer response.")
            var withoutResponse = false

            mutating func run() async throws {
                let filters = try dates.normalizedFilters(territory: territory)
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadReviews(
                    runtime: runtime,
                    filters: filters,
                    ratings: rating,
                    withResponse: withResponse,
                    withoutResponse: withoutResponse,
                    fetchOptions: fetchOptions,
                    refresh: fetch.refresh
                )
                let payload = reviewsSummary(from: try filteredReviews(
                    runtime: runtime,
                    filters: filters,
                    ratings: rating,
                    withResponse: withResponse,
                    withoutResponse: withoutResponse
                ))
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Respond: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Argument(help: "Customer review ID.")
            var reviewID: String
            @Option(help: "Reply body.")
            var body: String

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                let payload = try await runtime.client!.createOrUpdateCustomerReviewResponse(reviewID: reviewID, responseBody: body)
                try OutputRenderer.write(payload, format: global.output)
            }
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Probe.self, Audit.self, Reconcile.self])

        struct Probe: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                try await runtime.client?.validateToken()
                try await preloadHealthData(runtime: runtime, refresh: false)
                try OutputRenderer.write(
                    [
                        "auth": "ok",
                        "salesCoverageDays": "\(try runtime.analytics.health().salesCoverageDays)",
                        "financeCoverageMonths": "\(try runtime.analytics.health().financeCoverageMonths)"
                    ],
                    format: global.output
                )
            }
        }

        struct Audit: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials)
                try OutputRenderer.write(try await runtime.analytics.audit(), format: global.output)
            }
        }

        struct Reconcile: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @OptionGroup var dates: DateSelectionOptions
            @OptionGroup var fetch: FetchControlOptions

            mutating func run() async throws {
                let filters = try dates.normalizedFilters()
                let runtime = try makeRuntime(credentials: credentials, offline: fetch.offline)
                try await preloadSourceData(runtime: runtime, source: .sales, filters: filters, refresh: fetch.refresh)
                try await preloadSourceData(runtime: runtime, source: .finance, filters: filters, refresh: fetch.refresh)
                let payload = try await runtime.analytics.reconcile(filters: filters)
                try OutputRenderer.write(payload, format: global.output)
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
                try OutputRenderer.write(["status": "cleared", "path": runtime.paths.cacheRoot.path], format: global.output)
            }
        }
    }

    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Advanced prefetch commands. Most users can query directly.",
            subcommands: [Sales.self, Subscriptions.self, Finance.self, ReviewsSync.self]
        )

        struct Sales: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Specific PT date to prefetch. Repeat for multiple days.")
            var date: [String] = []
            @Option(help: "Recent PT days to prefetch when --date is omitted.")
            var days: Int = 1
            @Option(help: "Fiscal month to prefetch, YYYY-MM. Repeat for multiple months.")
            var month: [String] = []
            @Flag(help: "Ignore cache and redownload.")
            var force = false

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                let dates = try date.isEmpty ? recentPTDates(days: days) : date.map(parsePTDateInput)
                let summary = try await runtime.syncService!.syncSales(dates: dates, monthlyFiscalMonths: month, force: force)
                try OutputRenderer.write(summary, format: global.output)
            }
        }

        struct Subscriptions: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Specific PT date to prefetch. Repeat for multiple days.")
            var date: [String] = []
            @Option(help: "Recent PT days to prefetch when --date is omitted.")
            var days: Int = 1
            @Flag(help: "Ignore cache and redownload.")
            var force = false

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                let dates = try date.isEmpty ? recentPTDates(days: days) : date.map(parsePTDateInput)
                let summary = try await runtime.syncService!.syncSubscriptions(dates: dates, force: force)
                try OutputRenderer.write(summary, format: global.output)
            }
        }

        struct Finance: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Fiscal month to prefetch, YYYY-MM. Repeat for multiple months.")
            var month: [String] = []
            @Option(help: "Recent fiscal months to prefetch when --month is omitted.")
            var months: Int = 1
            @Flag(help: "Ignore cache and redownload.")
            var force = false

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                let fiscalMonths = month.isEmpty ? recentFiscalMonths(count: months) : month.sorted()
                let summary = try await runtime.syncService!.syncFinance(
                    fiscalMonths: fiscalMonths,
                    regionCodes: ["ZZ", "Z1"],
                    reportTypes: [.financial, .financeDetail],
                    force: force
                )
                try OutputRenderer.write(summary, format: global.output)
            }
        }

        struct ReviewsSync: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "reviews")

            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Max apps to scan.")
            var maxApps: Int?
            @Option(help: "Max reviews per app.")
            var perAppLimit: Int?
            @Option(help: "Total review limit.")
            var totalLimit: Int?
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Rating filter. Repeat for multiple ratings.")
            var rating: [Int] = []
            @Flag(help: "Only include reviews with developer response.")
            var withResponse = false
            @Flag(help: "Only include reviews without developer response.")
            var withoutResponse = false

            mutating func run() async throws {
                let runtime = try makeRuntime(credentials: credentials, requireCredentials: true)
                let query = ASCCustomerReviewQuery(
                    sort: .newest,
                    ratings: Set(rating),
                    territory: territory,
                    hasPublishedResponse: responseState(withResponse: withResponse, withoutResponse: withoutResponse)
                )
                let summary = try await runtime.syncService!.syncReviews(
                    maxApps: maxApps,
                    perAppLimit: perAppLimit,
                    totalLimit: totalLimit,
                    query: query
                )
                try OutputRenderer.write(summary, format: global.output)
            }
        }
    }
}
