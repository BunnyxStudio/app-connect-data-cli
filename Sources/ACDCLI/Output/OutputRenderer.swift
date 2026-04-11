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
import ACDAnalytics
import ArgumentParser

enum OutputFormat: String, ExpressibleByArgument {
    case json
    case table
    case markdown
}

enum OutputRenderer {
    static func write<T: Encodable>(_ value: T, format: OutputFormat) throws {
        Swift.print(try render(value, format: format))
    }

    static func render<T: Encodable>(_ value: T, format: OutputFormat) throws -> String {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        case .table:
            return wrapTableOutput(renderTable(value))
        case .markdown:
            return renderMarkdown(value)
        }
    }

    private static func renderTable<T: Encodable>(_ value: T) -> String {
        if let result = value as? QueryResult {
            return renderQueryResult(result, format: .table)
        }
        if let report = value as? BriefSummaryReport {
            return renderBriefSummary(report, format: .table)
        }
        if let tableModel = value as? TableModel {
            return renderTableModel(tableModel)
        }
        if let descriptors = value as? [CapabilityDescriptor] {
            return renderCapabilities(descriptors, format: .table)
        }
        if let records = value as? [QueryRecord] {
            return renderTableModel(recordsTableModel(records))
        }
        if let dictionary = value as? [String: String] {
            return renderDictionaryRows([dictionary])
        }
        if let rows = value as? [[String: String]] {
            return renderDictionaryRows(rows)
        }
        return (try? render(value, format: .json)) ?? ""
    }

    private static func renderMarkdown<T: Encodable>(_ value: T) -> String {
        if let result = value as? QueryResult {
            return renderQueryResult(result, format: .markdown)
        }
        if let report = value as? BriefSummaryReport {
            return renderBriefSummary(report, format: .markdown)
        }
        if let tableModel = value as? TableModel {
            return renderMarkdownTable(tableModel)
        }
        if let descriptors = value as? [CapabilityDescriptor] {
            return renderCapabilities(descriptors, format: .markdown)
        }
        if let records = value as? [QueryRecord] {
            return renderMarkdownTable(recordsTableModel(records))
        }
        return (try? render(value, format: .json)) ?? ""
    }

    private static func renderQueryResult(_ result: QueryResult, format: OutputFormat) -> String {
        let body: String
        switch format {
        case .json:
            return (try? render(result, format: .json)) ?? ""
        case .table:
            body = result.tableModel.map(renderTableModel) ?? ""
        case .markdown:
            body = result.tableModel.map(renderMarkdownTable) ?? ""
        }

        let warnings = renderWarnings(result.warnings, format: format)
        if body.isEmpty {
            let emptyState = noDataMessage(format: format)
            if warnings.isEmpty {
                return emptyState
            }
            return emptyState + "\n\n" + warnings
        }
        if warnings.isEmpty {
            return body
        }
        return body + "\n\n" + warnings
    }

    private static func renderTableModel(_ tableModel: TableModel) -> String {
        let presented = presentedTableModel(tableModel)
        guard presented.columns.isEmpty == false else { return "" }
        let body = table(headers: presented.columns, rows: presented.rows.map { $0.map(normalizeCell) })
        guard let title = presented.title, title.isEmpty == false else { return body }
        return formatTableTitle(title) + "\n\n" + body
    }

    private static func renderMarkdownTable(_ tableModel: TableModel) -> String {
        let presented = presentedTableModel(tableModel)
        guard presented.columns.isEmpty == false else { return "" }
        let header = "| " + presented.columns.joined(separator: " | ") + " |"
        let divider = "| " + presented.columns.map { String(repeating: "-", count: max(3, $0.count)) }.joined(separator: " | ") + " |"
        let rows = presented.rows.map { "| " + $0.map(normalizeCell).joined(separator: " | ") + " |" }
        let body = ([header, divider] + rows).joined(separator: "\n")
        guard let title = presented.title, title.isEmpty == false else { return body }
        return "## \(title)\n\n" + body
    }

    private static func recordsTableModel(_ records: [QueryRecord]) -> TableModel {
        guard records.isEmpty == false else {
            return TableModel(columns: [], rows: [])
        }
        let dimensionKeys = Set(records.flatMap { $0.dimensions.keys }).sorted()
        let metricKeys = Set(records.flatMap { $0.metrics.keys }).sorted()
        let columns = dimensionKeys + metricKeys
        let rows = records.map { record in
            columns.map { key in
                if let value = record.dimensions[key] {
                    return normalizeCell(value)
                }
                if let value = record.metrics[key] {
                    return formatNumber(value)
                }
                return "-"
            }
        }
        return TableModel(columns: columns, rows: rows)
    }

    private static func renderDictionaryRows(_ rows: [[String: String]]) -> String {
        guard rows.isEmpty == false else { return "" }
        let columns = Set(rows.flatMap(\.keys)).sorted()
        return table(
            headers: columns,
            rows: rows.map { row in columns.map { normalizeCell(row[$0] ?? "") } }
        )
    }

    private static func renderWarnings(_ warnings: [QueryWarning], format: OutputFormat) -> String {
        guard warnings.isEmpty == false else { return "" }
        switch format {
        case .json:
            return ""
        case .table:
            return warnings.map { "Warning [\($0.code)]: \($0.message)" }.joined(separator: "\n")
        case .markdown:
            return warnings.map { "> Warning [\($0.code)]: \($0.message)" }.joined(separator: "\n")
        }
    }

    private static func renderBriefSummary(_ report: BriefSummaryReport, format: OutputFormat) -> String {
        switch format {
        case .json:
            return (try? render(report, format: .json)) ?? ""
        case .table:
            return renderBriefSummaryTable(report)
        case .markdown:
            return renderBriefSummaryMarkdown(report)
        }
    }

    private static func renderBriefSummaryTable(_ report: BriefSummaryReport) -> String {
        var blocks: [String] = [
            formatTableTitle(report.title),
            "Current: \(report.currentLabel)",
            "Compare: \(report.compareLabel)",
            "Currency: \(report.reportingCurrency)",
            "Time basis: \(report.timeBasis)"
        ]

        let warnings = renderWarnings(report.warnings, format: .table)
        if warnings.isEmpty == false {
            blocks.append(warnings)
        }

        for section in report.sections {
            var lines = [formatTableTitle(section.title)]
            if let note = section.note, note.isEmpty == false {
                lines.append("")
                lines.append(note)
            }
            let body = renderTableModel(section.table)
            if body.isEmpty == false {
                lines.append("")
                lines.append(body)
            }
            blocks.append(lines.joined(separator: "\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func formatTableTitle(_ title: String) -> String {
        "==== \(title) ===="
    }

    private static func renderBriefSummaryMarkdown(_ report: BriefSummaryReport) -> String {
        var blocks: [String] = [
            "# \(report.title)",
            "- Current: \(report.currentLabel)\n- Compare: \(report.compareLabel)\n- Currency: \(report.reportingCurrency)\n- Time basis: \(report.timeBasis)"
        ]

        let warnings = renderWarnings(report.warnings, format: .markdown)
        if warnings.isEmpty == false {
            blocks.append(warnings)
        }

        for section in report.sections {
            var lines = ["## \(section.title)"]
            if let note = section.note, note.isEmpty == false {
                lines.append(section.note ?? "")
            }
            let body = renderMarkdownTable(section.table)
            if body.isEmpty == false {
                lines.append(body)
            }
            blocks.append(lines.joined(separator: "\n\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func wrapTableOutput(_ value: String) -> String {
        guard value.isEmpty == false else { return value }
        return "\n\(value)\n"
    }

    private static func noDataMessage(format: OutputFormat) -> String {
        switch format {
        case .json:
            return ""
        case .table, .markdown:
            return "No data for the selected query."
        }
    }

    private static func renderCapabilities(_ descriptors: [CapabilityDescriptor], format: OutputFormat) -> String {
        switch format {
        case .json:
            return (try? render(descriptors, format: .json)) ?? ""
        case .table:
            return descriptors.map { descriptor in
                [
                    formatTableTitle(displayLabel(forTitle: descriptor.name)),
                    "Status: \(descriptor.status)",
                    "Time: \(descriptor.timeSupport.map(displayCapabilityToken).joined(separator: ", "))",
                    "Filters: \(descriptor.filterSupport.map(displayCapabilityToken).joined(separator: ", "))",
                    "Can query:",
                    descriptor.whatYouCanQuery.map { "- \($0)" }.joined(separator: "\n"),
                    "Cannot query:",
                    descriptor.whatYouCannotQuery.map { "- \($0)" }.joined(separator: "\n"),
                    "Notes:",
                    descriptor.notes.map { "- \($0)" }.joined(separator: "\n")
                ].joined(separator: "\n")
            }.joined(separator: "\n\n")
        case .markdown:
            return "# Capabilities\n\n" + descriptors.map { descriptor in
                [
                    "## \(displayLabel(forTitle: descriptor.name))",
                    "- Status: `\(descriptor.status)`",
                    "- Time: \(descriptor.timeSupport.map(displayCapabilityToken).joined(separator: ", "))",
                    "- Filters: \(descriptor.filterSupport.map(displayCapabilityToken).joined(separator: ", "))",
                    "- Can query:",
                    descriptor.whatYouCanQuery.map { "  - \($0)" }.joined(separator: "\n"),
                    "- Cannot query:",
                    descriptor.whatYouCannotQuery.map { "  - \($0)" }.joined(separator: "\n"),
                    "- Notes:",
                    descriptor.notes.map { "  - \($0)" }.joined(separator: "\n")
                ].joined(separator: "\n")
            }.joined(separator: "\n\n")
        }
    }

    private static func presentedTableModel(_ tableModel: TableModel) -> TableModel {
        TableModel(
            title: tableModel.title.map(displayLabel(forTitle:)),
            columns: tableModel.columns.map(displayLabel(forColumn:)),
            rows: tableModel.rows
        )
    }

    private static func displayLabel(forTitle raw: String) -> String {
        switch raw {
        case "sales":
            return "Sales"
        case "reviews":
            return "Reviews"
        case "finance":
            return "Finance"
        case "analytics":
            return "Analytics"
        default:
            return raw
        }
    }

    private static func displayLabel(forColumn raw: String) -> String {
        if raw.hasSuffix(" current") {
            let base = String(raw.dropLast(" current".count))
            return "\(displayLabel(forColumn: base)) (Current)"
        }
        if raw.hasSuffix(" previous") {
            let base = String(raw.dropLast(" previous".count))
            return "\(displayLabel(forColumn: base)) (Compare)"
        }
        if raw.hasSuffix(" delta%") {
            let base = String(raw.dropLast(" delta%".count))
            return "\(displayLabel(forColumn: base)) (% Change)"
        }
        if raw.hasSuffix(" delta") {
            let base = String(raw.dropLast(" delta".count))
            return "\(displayLabel(forColumn: base)) (Change)"
        }

        switch raw {
        case "app":
            return "App"
        case "averageRating":
            return "Average Rating"
        case "billingRetry":
            return "Billing Retry"
        case "bundleID":
            return "Bundle ID"
        case "change":
            return "% Change"
        case "compare":
            return "Compare"
        case "count":
            return "Count"
        case "current":
            return "Current"
        case "customerCurrency":
            return "Customer Currency"
        case "date":
            return "Date"
        case "device":
            return "Device"
        case "displayTimeZone":
            return "Display Time Zone"
        case "financeFiscalMonth":
            return "Finance Fiscal Month"
        case "financeRows":
            return "Finance Rows"
        case "fiscalMonth":
            return "Fiscal Month"
        case "gracePeriod":
            return "Grace Period"
        case "installs":
            return "Install Units"
        case "lowRatingRatio":
            return "Low Rating Share"
        case "nextRolloverLocal":
            return "Next Apple Rollover"
        case "pageViews":
            return "Page Views"
        case "platform":
            return "Platform"
        case "proceeds":
            return "Proceeds"
        case "purchases":
            return "Purchase Units"
        case "qualifiedConversions":
            return "Qualified Conversions"
        case "rating":
            return "Rating"
        case "repliedRate":
            return "Reply Rate"
        case "reportingCurrency":
            return "Reporting Currency"
        case "reportType":
            return "Report Type"
        case "responseState":
            return "Response State"
        case "reviewCoverageDays":
            return "Review Coverage Days"
        case "reviewsAsOf":
            return "Reviews As Of"
        case "salesAsOf":
            return "Sales As Of"
        case "salesCoverageDays":
            return "Sales Coverage Days"
        case "sku":
            return "SKU"
        case "sourceReport":
            return "Source Report"
        case "startDatePT":
            return "Start Date (PT)"
        case "subscription":
            return "Subscription"
        case "subscriptionAsOf":
            return "Subscription Snapshot As Of"
        case "subscriptionCoverageDays":
            return "Subscription Coverage Days"
        case "territory":
            return "Territory"
        case "units":
            return "Units"
        default:
            return humanizeIdentifier(raw)
        }
    }

    private static func humanizeIdentifier(_ raw: String) -> String {
        let separated = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
        return separated
            .split(separator: " ")
            .map { token in
                let lower = token.lowercased()
                switch lower {
                case "pt":
                    return "PT"
                case "id":
                    return "ID"
                case "sku":
                    return "SKU"
                default:
                    return lower.prefix(1).uppercased() + lower.dropFirst()
                }
            }
            .joined(separator: " ")
    }

    private static func displayCapabilityToken(_ raw: String) -> String {
        switch raw {
        case "version":
            return "app-version"
        case "responseState":
            return "response-state"
        case "sourceReport":
            return "source-report"
        case "fiscalMonth":
            return "fiscal-month"
        case "fiscalYear":
            return "fiscal-year"
        default:
            return raw
        }
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        guard headers.isEmpty == false else { return "" }
        let widths = headers.enumerated().map { index, header in
            max(header.count, rows.map { $0.indices.contains(index) ? $0[index].count : 0 }.max() ?? 0)
        }
        let headerLine = zip(headers, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: " | ")
        let divider = widths.map { String(repeating: "-", count: $0) }.joined(separator: "-|-")
        let rowLines = rows.map { row in
            widths.indices.map { index in
                let value = row.indices.contains(index) ? row[index] : ""
                return value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: " | ")
        }
        return ([headerLine, divider] + rowLines).joined(separator: "\n")
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private static func normalizeCell(_ value: String) -> String {
        value.isEmpty ? "-" : value
    }
}
