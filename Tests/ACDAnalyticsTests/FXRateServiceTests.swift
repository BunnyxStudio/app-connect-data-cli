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
@testable import ACDAnalytics

final class FXRateServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testResolveUSDRatesUsesV2QuotePayloadAndCachesSourceDate() async throws {
        let temp = try makeTempDirectory()
        let cacheURL = temp.appendingPathComponent("fx-rates.json")
        let session = makeSession()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.frankfurter.dev")
            XCTAssertEqual(request.url?.path, "/v2/rates")
            let data = """
            [
              {"date":"2026-04-04","base":"USD","quote":"KZT","rate":472.49},
              {"date":"2026-04-05","base":"USD","quote":"RUB","rate":80.17},
              {"date":"2026-04-03","base":"USD","quote":"TWD","rate":31.962}
            ]
            """.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let service = FXRateService(cacheURL: cacheURL, session: session)
        let rates = try await service.resolveUSDRates(for: [
            FXLookupRequest(dateKey: "2026-04-05", currencyCode: "KZT"),
            FXLookupRequest(dateKey: "2026-04-05", currencyCode: "RUB"),
            FXLookupRequest(dateKey: "2026-04-05", currencyCode: "TWD")
        ])

        XCTAssertEqual(try XCTUnwrap(rates[FXLookupRequest(dateKey: "2026-04-05", currencyCode: "KZT")]), 1 / 472.49, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(rates[FXLookupRequest(dateKey: "2026-04-05", currencyCode: "RUB")]), 1 / 80.17, accuracy: 0.0000001)
        XCTAssertEqual(try XCTUnwrap(rates[FXLookupRequest(dateKey: "2026-04-05", currencyCode: "TWD")]), 1 / 31.962, accuracy: 0.0000001)

        let data = try Data(contentsOf: cacheURL)
        let cache = try JSONDecoder().decode([String: CachedRateRecord].self, from: data)
        XCTAssertEqual(cache["2026-04-05|KZT"]?.requestDateKey, "2026-04-05")
        XCTAssertEqual(cache["2026-04-05|KZT"]?.sourceDateKey, "2026-04-04")
        XCTAssertEqual(cache["2026-04-05|RUB"]?.sourceDateKey, "2026-04-05")
        XCTAssertEqual(cache["2026-04-05|TWD"]?.sourceDateKey, "2026-04-03")
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct CachedRateRecord: Decodable {
    var requestDateKey: String
    var sourceDateKey: String
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
