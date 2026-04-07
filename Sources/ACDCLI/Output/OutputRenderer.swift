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

enum OutputFormat: String, ExpressibleByArgument {
    case json
    case table
    case markdown
}

enum OutputRenderer {
    static func write<T: Encodable>(_ value: T, format: OutputFormat) throws {
        let output = try render(value, format: format)
        Swift.print(output)
    }

    static func render<T: Encodable>(_ value: T, format: OutputFormat) throws -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        case .table:
            return renderTable(value)
        case .markdown:
            return renderMarkdown(value)
        }
    }

    private static func renderTable<T: Encodable>(_ value: T) -> String {
        switch value {
        case let snapshot as DashboardSnapshot:
            return keyValueTable([
                ("source", snapshot.source.rawValue),
                ("totalUnits", number(snapshot.totalUnits)),
                ("totalPurchases", number(snapshot.totalPurchases)),
                ("totalInstalls", number(snapshot.totalInstalls)),
                ("refunds", number(snapshot.refundCount)),
                ("dataAsOfPT", snapshot.dataAsOfPT?.ptDateString ?? "-")
            ])
        case let health as DataHealthSnapshot:
            return keyValueTable([
                ("salesAsOfPT", health.salesAsOfPT?.ptDateString ?? "-"),
                ("subscriptionAsOfPT", health.subscriptionAsOfPT?.ptDateString ?? "-"),
                ("financeAsOfPT", health.financeAsOfPT?.fiscalMonthString ?? "-"),
                ("salesCoverageDays", "\(health.salesCoverageDays)"),
                ("financeCoverageMonths", "\(health.financeCoverageMonths)"),
                ("confidence", health.confidence.rawValue)
            ])
        case let modules as DashboardModuleSnapshot:
            return keyValueTable([
                ("salesBookingUSD", number(modules.overview.salesBookingUSD)),
                ("financeRecognizedUSD", number(modules.overview.financeRecognizedUSD)),
                ("activeSubscriptions", number(modules.subscription.activeSubscriptions)),
                ("financeRows", "\(modules.finance.financeRows)"),
                ("confidence", modules.dataHealth.confidence.rawValue)
            ])
        case let products as [TopProductRow]:
            return table(
                headers: ["name", "kind", "proceeds", "currency", "units"],
                rows: products.map { [$0.name, $0.kind.rawValue, number($0.proceeds), $0.currency, number($0.units)] }
            )
        case let trend as [TrendPoint]:
            return table(
                headers: ["date", "units", "usd"],
                rows: trend.map { [$0.date.ptDateString, number($0.units), number($0.proceedsByCurrency["USD"] ?? 0)] }
            )
        case let reviews as [ASCLatestReview]:
            return table(
                headers: ["date", "app", "rating", "territory", "response", "title"],
                rows: reviews.map {
                    [
                        $0.createdDate.ptDateString,
                        $0.appName,
                        "\($0.rating)",
                        ($0.territory ?? "-"),
                        $0.developerResponse == nil ? "no" : "yes",
                        $0.title
                    ]
                }
            )
        case let summary as ReviewsSummarySnapshot:
            return keyValueTable([
                ("total", "\(summary.total)"),
                ("averageRating", number(summary.averageRating)),
                ("unresolvedResponses", "\(summary.unresolvedResponses)"),
                ("latestDate", summary.latestDate?.ptDateString ?? "-")
            ])
        case let sync as SyncSummary:
            if sync.records.isEmpty {
                return keyValueTable([("reviewCount", "\(sync.reviewCount)")])
            }
            return table(
                headers: ["source", "type", "subtype", "dateKey", "fetchedAt"],
                rows: sync.records.map {
                    [$0.source.rawValue, $0.reportType, $0.reportSubType, $0.reportDateKey, ISO8601DateFormatter().string(from: $0.fetchedAt)]
                }
            )
        case let audit as DoctorAuditSnapshot:
            return keyValueTable([
                ("totalReports", "\(audit.totalReports)"),
                ("totalReviewItems", "\(audit.totalReviewItems)"),
                ("unknownCurrencyRows", "\(audit.unknownCurrencyRows)"),
                ("latestSalesDatePT", audit.latestSalesDatePT ?? "-"),
                ("latestFinanceMonth", audit.latestFinanceMonth ?? "-")
            ])
        case let reconcile as ReconcileSnapshot:
            return keyValueTable([
                ("salesUSD", number(reconcile.salesUSD)),
                ("financeUSD", number(reconcile.financeUSD)),
                ("diffUSD", number(reconcile.diffUSD))
            ])
        default:
            return "table output is not implemented for this payload"
        }
    }

    private static func renderMarkdown<T: Encodable>(_ value: T) -> String {
        switch value {
        case let snapshot as DashboardSnapshot:
            return """
            # Snapshot

            - Source: `\(snapshot.source.rawValue)`
            - Total units: `\(number(snapshot.totalUnits))`
            - Total purchases: `\(number(snapshot.totalPurchases))`
            - Total installs: `\(number(snapshot.totalInstalls))`
            - Refunds: `\(number(snapshot.refundCount))`
            - Data as of PT: `\(snapshot.dataAsOfPT?.ptDateString ?? "-")`
            """
        case let products as [TopProductRow]:
            let body = products.map { "- \($0.name): `\(number($0.proceeds))` \($0.currency), units `\(number($0.units))`" }.joined(separator: "\n")
            return "# Top Products\n\n\(body)"
        case let reviews as [ASCLatestReview]:
            let body = reviews.map {
                "- `\($0.createdDate.ptDateString)` \($0.appName) \($0.rating)★ \($0.territory ?? "-"): \($0.title)"
            }.joined(separator: "\n")
            return "# Reviews\n\n\(body)"
        default:
            return (try? render(value, format: .json)) ?? ""
        }
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        let widths = headers.enumerated().map { index, header in
            max(header.count, rows.map { $0.indices.contains(index) ? $0[index].count : 0 }.max() ?? 0)
        }
        let headerLine = zip(headers, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " | ")
        let divider = widths.map { String(repeating: "-", count: $0) }.joined(separator: "-|-")
        let rowLines = rows.map { row in
            zip(row, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " | ")
        }
        return ([headerLine, divider] + rowLines).joined(separator: "\n")
    }

    private static func keyValueTable(_ pairs: [(String, String)]) -> String {
        table(headers: ["key", "value"], rows: pairs.map { [$0.0, $0.1] })
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
