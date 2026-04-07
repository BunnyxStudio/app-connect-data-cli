import XCTest
import Foundation
@testable import ACDCore

final class DataCompressionTests: XCTestCase {
    func testInvalidGzipThrows() {
        XCTAssertThrowsError(try Data("not-gzip".utf8).gunzipped())
    }
}
