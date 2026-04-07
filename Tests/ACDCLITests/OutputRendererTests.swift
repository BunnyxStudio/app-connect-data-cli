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
