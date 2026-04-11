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

import XCTest
import Foundation
@testable import ACDCLI
@testable import ACDAnalytics

final class OutputRendererTests: XCTestCase {
    func testTableRenderUsesQueryResultTableModel() throws {
        let rendered = try OutputRenderer.render(
            QueryResult(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeEnvelope(label: "last week", startDatePT: "2026-02-10", endDatePT: "2026-02-16"),
                filters: QueryFilterSet(),
                source: ["summary-sales"],
                data: QueryResultData(aggregates: [
                    QueryAggregateRow(group: [:], metrics: ["proceeds": 120])
                ]),
                tableModel: TableModel(
                    columns: ["proceeds"],
                    rows: [["120.00"]]
                )
            ),
            format: .table
        )

        XCTAssertTrue(rendered.contains("Proceeds"))
        XCTAssertTrue(rendered.contains("120.00"))
    }

    func testMarkdownRenderForCapabilities() throws {
        let rendered = try OutputRenderer.render(
            [
                CapabilityDescriptor(
                    name: "sales",
                    status: "included",
                    whatYouCanQuery: ["Summary Sales"],
                    whatYouCannotQuery: ["User profiles"],
                    timeSupport: ["date"],
                    filterSupport: ["app", "version", "sourceReport", "responseState"],
                    notes: ["Apple-only"]
                )
            ],
            format: .markdown
        )

        XCTAssertTrue(rendered.contains("# Capabilities"))
        XCTAssertTrue(rendered.contains("## Sales"))
        XCTAssertTrue(rendered.contains("Time: date"))
        XCTAssertTrue(rendered.contains("app-version"))
        XCTAssertTrue(rendered.contains("source-report"))
        XCTAssertTrue(rendered.contains("response-state"))
    }

    func testTableRenderIncludesWarningsForQueryResult() throws {
        let rendered = try OutputRenderer.render(
            QueryResult(
                dataset: .sales,
                operation: .aggregate,
                time: QueryTimeEnvelope(label: "last week", startDatePT: "2026-02-10", endDatePT: "2026-02-16"),
                filters: QueryFilterSet(),
                source: ["summary-sales"],
                data: QueryResultData(aggregates: [
                    QueryAggregateRow(group: [:], metrics: ["proceeds": 120])
                ]),
                warnings: [
                    QueryWarning(
                        code: "currency-normalized",
                        message: "Monetary metrics are normalized to CNY."
                    )
                ],
                tableModel: TableModel(
                    columns: ["proceeds"],
                    rows: [["120.00"]]
                )
            ),
            format: .table
        )

        XCTAssertTrue(rendered.contains("Proceeds"))
        XCTAssertTrue(rendered.contains("Warning [currency-normalized]: Monetary metrics are normalized to CNY."))
    }

    func testTableRenderAddsBlankLineAroundOutput() throws {
        let rendered = try OutputRenderer.render(
            TableModel(
                columns: ["metric", "value"],
                rows: [["Sales proceeds", "120.00"]]
            ),
            format: .table
        )

        XCTAssertTrue(rendered.hasPrefix("\nMetric"))
        XCTAssertTrue(rendered.hasSuffix("\n"))
    }

    func testTableRenderForBriefSummaryUsesSeparateTables() throws {
        let rendered = try OutputRenderer.render(
            BriefSummaryReport(
                period: "weekly",
                title: "Week to Date Summary",
                currentLabel: "this week to date (2026-04-01 to 2026-04-07 PT)",
                compareLabel: "previous week same progress (2026-03-25 to 2026-03-31 PT)",
                reportingCurrency: "CNY",
                timeBasis: "Apple business dates use PT. Next daily rollover in Asia/Shanghai: 2026-04-08 19:00 CST.",
                sections: [
                    BriefSummarySection(
                        title: "Overview",
                        note: "Important metrics.",
                        table: TableModel(
                            columns: ["metric", "current"],
                            rows: [["Sales Proceeds", "CNY 100.00"]]
                        )
                    ),
                    BriefSummarySection(
                        title: "Top Products",
                        note: nil,
                        table: TableModel(
                            columns: ["product", "proceeds"],
                            rows: [["Pro", "CNY 80.00"]]
                        )
                    )
                ],
                warnings: [
                    QueryWarning(code: "fx", message: "Monetary metrics are normalized to CNY.")
                ]
            ),
            format: .table
        )

        XCTAssertTrue(rendered.contains("Week to Date Summary"))
        XCTAssertTrue(rendered.contains("==== Overview ===="))
        XCTAssertTrue(rendered.contains("==== Top Products ===="))
        XCTAssertTrue(rendered.contains("Time basis: Apple business dates use PT."))
        XCTAssertTrue(rendered.contains("Warning [fx]: Monetary metrics are normalized to CNY."))
        XCTAssertTrue(rendered.contains("==== Overview ====\n\nImportant metrics.\n\nMetric"))
    }

    func testTableRenderHumanizesTableHeaders() throws {
        let rendered = try OutputRenderer.render(
            QueryResult(
                dataset: .reviews,
                operation: .compare,
                time: QueryTimeEnvelope(label: "last week", startDatePT: "2026-02-10", endDatePT: "2026-02-16"),
                filters: QueryFilterSet(),
                source: ["customer-reviews"],
                data: QueryResultData(comparisons: []),
                tableModel: TableModel(
                    title: "reviews",
                    columns: ["sourceReport", "averageRating current", "averageRating delta%"],
                    rows: [["customer-reviews", "4.60", "+3.0%"]]
                )
            ),
            format: .table
        )

        XCTAssertTrue(rendered.contains("==== Reviews ===="))
        XCTAssertTrue(rendered.contains("Source Report"))
        XCTAssertTrue(rendered.contains("Average Rating (Current)"))
        XCTAssertTrue(rendered.contains("Average Rating (% Change)"))
    }

    func testEmptyQueryResultShowsNoDataState() throws {
        let table = try OutputRenderer.render(
            QueryResult(
                dataset: .reviews,
                operation: .aggregate,
                time: QueryTimeEnvelope(label: "last week", startDatePT: "2026-02-10", endDatePT: "2026-02-16"),
                filters: QueryFilterSet(),
                source: ["customer-reviews"],
                data: QueryResultData(aggregates: []),
                tableModel: TableModel(columns: [], rows: [])
            ),
            format: .table
        )
        let markdown = try OutputRenderer.render(
            QueryResult(
                dataset: .reviews,
                operation: .aggregate,
                time: QueryTimeEnvelope(label: "last week", startDatePT: "2026-02-10", endDatePT: "2026-02-16"),
                filters: QueryFilterSet(),
                source: ["customer-reviews"],
                data: QueryResultData(aggregates: []),
                tableModel: TableModel(columns: [], rows: [])
            ),
            format: .markdown
        )

        XCTAssertTrue(table.contains("No data for the selected query."))
        XCTAssertTrue(markdown.contains("No data for the selected query."))
    }

    func testEmptyTitledTableModelStillShowsNoDataState() throws {
        let rendered = try OutputRenderer.render(
            QueryResult(
                dataset: .analytics,
                operation: .records,
                time: QueryTimeEnvelope(label: "today", startDatePT: "2026-04-09", endDatePT: "2026-04-09"),
                filters: QueryFilterSet(),
                source: ["usage"],
                data: QueryResultData(records: []),
                warnings: [QueryWarning(code: "analytics-privacy", message: "Privacy thresholds may omit rows.")],
                tableModel: TableModel(title: "analytics", columns: [], rows: [])
            ),
            format: .table
        )

        XCTAssertTrue(rendered.contains("No data for the selected query."))
        XCTAssertTrue(rendered.contains("Warning [analytics-privacy]: Privacy thresholds may omit rows."))
        XCTAssertFalse(rendered.contains("==== Analytics ===="))
    }
}
