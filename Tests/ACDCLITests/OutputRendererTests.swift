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
                dataset: .brief,
                operation: .brief,
                time: QueryTimeEnvelope(label: "last week", startDatePT: "2026-02-10", endDatePT: "2026-02-16"),
                filters: QueryFilterSet(),
                source: ["summary-sales"],
                data: QueryResultData(brief: [
                    BriefRow(metric: "Sales proceeds", current: "$120.00", compare: "$100.00", change: "20.00%", note: "up")
                ]),
                tableModel: TableModel(
                    columns: ["metric", "current", "compare", "change", "note"],
                    rows: [["Sales proceeds", "$120.00", "$100.00", "20.00%", "up"]]
                )
            ),
            format: .table
        )

        XCTAssertTrue(rendered.contains("metric"))
        XCTAssertTrue(rendered.contains("Sales proceeds"))
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
                    filterSupport: ["app", "territory"],
                    notes: ["Apple-only"]
                )
            ],
            format: .markdown
        )

        XCTAssertTrue(rendered.contains("# Capabilities"))
        XCTAssertTrue(rendered.contains("`sales`"))
    }
}
