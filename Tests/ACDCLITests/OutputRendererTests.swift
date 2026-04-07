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
    func testJSONRenderForHealth() throws {
        let rendered = try OutputRenderer.render(DataHealthSnapshot.empty, format: .json)
        XCTAssertTrue(rendered.contains("\"confidence\""))
    }

    func testTableRenderForReviewsSummary() throws {
        let rendered = try OutputRenderer.render(
            ReviewsSummarySnapshot(
                total: 1,
                averageRating: 5,
                histogram: [5: 1],
                byTerritory: [],
                unresolvedResponses: 1,
                latestDate: nil
            ),
            format: .table
        )
        XCTAssertTrue(rendered.contains("averageRating"))
    }
}
