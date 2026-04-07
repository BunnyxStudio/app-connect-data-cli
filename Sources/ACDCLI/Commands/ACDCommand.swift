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

@main
@available(macOS 10.15, *)
struct ACDCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "acd",
        abstract: "ACD-derived analytics CLI for App Store Connect reports and reviews.",
        subcommands: [Auth.self, Sync.self, Query.self, Reviews.self, Doctor.self, Cache.self]
    )
}

extension ACDCommand {
    struct Auth: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Validate.self])

        struct Validate: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
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

    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Sales.self, Subscriptions.self, Finance.self, ReviewsSync.self])

        struct Sales: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Specific PT date to sync. Repeat for multiple days.")
            var date: [String] = []
            @Option(help: "Recent PT days to sync when --date is omitted.")
            var days: Int = 1
            @Option(help: "Fiscal month to sync, YYYY-MM. Repeat for multiple months.")
            var month: [String] = []
            @Flag(help: "Ignore cache and redownload.")
            var force = false

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
                let dates = try date.isEmpty ? recentPTDates(days: days) : date.map(parsePTDateInput)
                let summary = try await runtime.syncService!.syncSales(dates: dates, monthlyFiscalMonths: month, force: force)
                try OutputRenderer.write(summary, format: global.output)
            }
        }

        struct Subscriptions: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Specific PT date to sync. Repeat for multiple days.")
            var date: [String] = []
            @Option(help: "Recent PT days to sync when --date is omitted.")
            var days: Int = 1
            @Flag(help: "Ignore cache and redownload.")
            var force = false

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
                let dates = try date.isEmpty ? recentPTDates(days: days) : date.map(parsePTDateInput)
                let summary = try await runtime.syncService!.syncSubscriptions(dates: dates, force: force)
                try OutputRenderer.write(summary, format: global.output)
            }
        }

        struct Finance: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "Fiscal month to sync, YYYY-MM. Repeat for multiple months.")
            var month: [String] = []
            @Option(help: "Recent fiscal months to sync when --month is omitted.")
            var months: Int = 1
            @Flag(help: "Ignore cache and redownload.")
            var force = false

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
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
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
                let query = ASCCustomerReviewQuery(
                    sort: .newest,
                    ratings: Set(rating),
                    territory: territory,
                    hasPublishedResponse: withResponse ? true : (withoutResponse ? false : nil)
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

    struct Query: AsyncParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Snapshot.self, Modules.self, Health.self, Trend.self, TopProducts.self, Run.self])

        struct Snapshot: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "sales or finance.")
            var source: DashboardDataSource = .sales
            @Option(help: "PT start date YYYY-MM-DD.")
            var start: String?
            @Option(help: "PT end date YYYY-MM-DD.")
            var end: String?
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Device filter.")
            var device: String?

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try await runtime.analytics.snapshot(
                    source: source,
                    filters: QueryFilters(startDatePT: start, endDatePT: end, territory: territory, device: device)
                )
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Modules: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "PT start date YYYY-MM-DD.")
            var start: String?
            @Option(help: "PT end date YYYY-MM-DD.")
            var end: String?
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Device filter.")
            var device: String?

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try await runtime.analytics.modules(
                    filters: QueryFilters(startDatePT: start, endDatePT: end, territory: territory, device: device)
                )
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Health: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try runtime.analytics.health()
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Trend: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "sales or finance.")
            var source: DashboardDataSource = .sales
            @Option(help: "PT start date YYYY-MM-DD.")
            var start: String?
            @Option(help: "PT end date YYYY-MM-DD.")
            var end: String?

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try await runtime.analytics.trend(
                    source: source,
                    filters: QueryFilters(startDatePT: start, endDatePT: end)
                )
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct TopProducts: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "top-products")

            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "sales or finance.")
            var source: DashboardDataSource = .sales
            @Option(help: "PT start date YYYY-MM-DD.")
            var start: String?
            @Option(help: "PT end date YYYY-MM-DD.")
            var end: String?
            @Option(help: "Limit.")
            var limit: Int = 10

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try await runtime.analytics.topProducts(
                    source: source,
                    filters: QueryFilters(startDatePT: start, endDatePT: end, limit: limit)
                )
                try OutputRenderer.write(payload, format: global.output)
            }
        }

        struct Run: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Argument(help: "Path to JSON spec or - for stdin.")
            var spec: String

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let data: Data
                if spec == "-" {
                    data = FileHandle.standardInput.readDataToEndOfFile()
                } else {
                    data = try Data(contentsOf: URL(fileURLWithPath: spec))
                }
                let querySpec = try JSONDecoder().decode(QuerySpec.self, from: data)
                switch querySpec.kind {
                case .snapshot:
                    let payload = try await runtime.analytics.snapshot(source: querySpec.source ?? .sales, filters: querySpec.filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .modules:
                    let payload = try await runtime.analytics.modules(filters: querySpec.filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .health:
                    let payload = try runtime.analytics.health()
                    try OutputRenderer.write(payload, format: global.output)
                case .trend:
                    let payload = try await runtime.analytics.trend(source: querySpec.source ?? .sales, filters: querySpec.filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .topProducts:
                    let payload = try await runtime.analytics.topProducts(source: querySpec.source ?? .sales, filters: querySpec.filters)
                    try OutputRenderer.write(payload, format: global.output)
                case .reviewsList:
                    let payload = try runtime.analytics.reviews()
                    try OutputRenderer.write(payload, format: global.output)
                case .reviewsSummary:
                    let payload = try runtime.analytics.reviewsSummary()
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
            @Option(help: "Limit.")
            var limit: Int = 50
            @Option(help: "Territory filter.")
            var territory: String?
            @Option(help: "Rating filter.")
            var rating: [Int] = []

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try runtime.analytics.reviews().filter { review in
                    let territoryMatches = territory.map { review.territory?.uppercased() == $0.uppercased() } ?? true
                    let ratingMatches = rating.isEmpty ? true : rating.contains(review.rating)
                    return territoryMatches && ratingMatches
                }
                try OutputRenderer.write(Array(payload.prefix(max(0, limit))), format: global.output)
            }
        }

        struct Summary: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                try OutputRenderer.write(try runtime.analytics.reviewsSummary(), format: global.output)
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
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
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
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: true)
                try await runtime.client?.validateToken()
                let sales = try await runtime.syncService!.syncSales(dates: recentPTDates(days: 1), monthlyFiscalMonths: [Date().fiscalMonthString], force: false)
                let finance = try await runtime.syncService!.syncFinance(fiscalMonths: recentFiscalMonths(count: 1), regionCodes: ["ZZ", "Z1"], reportTypes: [.financial, .financeDetail], force: false)
                try OutputRenderer.write(
                    [
                        "auth": "ok",
                        "salesRecords": "\(sales.records.count)",
                        "financeRecords": "\(finance.records.count)"
                    ],
                    format: global.output
                )
            }
        }

        struct Audit: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                try OutputRenderer.write(try await runtime.analytics.audit(), format: global.output)
            }
        }

        struct Reconcile: AsyncParsableCommand {
            @OptionGroup var global: GlobalOptions
            @OptionGroup var credentials: CredentialsOptions
            @Option(help: "PT start date YYYY-MM-DD.")
            var start: String?
            @Option(help: "PT end date YYYY-MM-DD.")
            var end: String?

            mutating func run() async throws {
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                let payload = try await runtime.analytics.reconcile(filters: QueryFilters(startDatePT: start, endDatePT: end))
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
                let runtime = try RuntimeFactory.make(overrides: credentials.overrides, requireCredentials: false)
                try runtime.cacheStore.clear()
                try OutputRenderer.write(["status": "cleared", "path": runtime.paths.cacheRoot.path], format: global.output)
            }
        }
    }
}
