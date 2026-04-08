import XCTest
import Foundation
@testable import ACDCore

final class ASCClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testReportNotAvailableYetErrorIncludesAvailabilityGuidance() throws {
        let error = ASCClientError.reportNotAvailableYet(
            "The request expected results but none were found - Report is not available yet."
        )

        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(description.contains("The request expected results but none were found - Report is not available yet."))
        XCTAssertTrue(description.contains("5 am PT"))
        XCTAssertTrue(description.contains("5 am JST"))
        XCTAssertTrue(description.contains("5 am CET"))
    }

    func testFetchLatestCustomerReviewsFetchesMultipleAppsConcurrently() async throws {
        let probe = ReviewConcurrencyProbe()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)

        StubURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/v1/apps" {
                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(
                        """
                        {
                          "data": [
                            {
                              "id": "1",
                              "type": "apps",
                              "attributes": {
                                "name": "App One",
                                "bundleId": "com.example.one"
                              }
                            },
                            {
                              "id": "2",
                              "type": "apps",
                              "attributes": {
                                "name": "App Two",
                                "bundleId": "com.example.two"
                              }
                            }
                          ]
                        }
                        """.utf8
                    )
                )
            }

            if url.path == "/v1/apps/1/customerReviews" || url.path == "/v1/apps/2/customerReviews" {
                await probe.begin()
                defer {
                    Task {
                        await probe.end()
                    }
                }
                try await Task.sleep(nanoseconds: 150_000_000)

                let payload: String
                if url.path.contains("/1/") {
                    payload =
                        """
                        {
                          "data": [
                            {
                              "id": "r1",
                              "type": "customerReviews",
                              "attributes": {
                                "rating": 5,
                                "title": "Great",
                                "body": "Nice",
                                "reviewerNickname": "A",
                                "territory": "US",
                                "createdDate": "2026-04-07T00:00:00Z"
                              }
                            }
                          ]
                        }
                        """
                } else {
                    payload =
                        """
                        {
                          "data": [
                            {
                              "id": "r2",
                              "type": "customerReviews",
                              "attributes": {
                                "rating": 4,
                                "title": "Good",
                                "body": "Solid",
                                "reviewerNickname": "B",
                                "territory": "JP",
                                "createdDate": "2026-04-06T00:00:00Z"
                              }
                            }
                          ]
                        }
                        """
                }

                return (
                    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(payload.utf8)
                )
            }

            throw URLError(.unsupportedURL)
        }

        let client = ASCClient(session: session, tokenProvider: { "TEST_TOKEN" })
        let reviews = try await client.fetchLatestCustomerReviews(maxApps: 2, pageLimit: 200)
        let maxInFlight = await probe.maxInFlight()

        XCTAssertEqual(reviews.count, 2)
        XCTAssertEqual(reviews.map(\.id), ["r1", "r2"])
        XCTAssertGreaterThanOrEqual(maxInFlight, 2)
    }
}

private actor ReviewConcurrencyProbe {
    private var inFlight = 0
    private var peak = 0

    func begin() {
        inFlight += 1
        peak = max(peak, inFlight)
    }

    func end() {
        inFlight = max(0, inFlight - 1)
    }

    func maxInFlight() -> Int {
        peak
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static nonisolated(unsafe) var requestHandler: (@Sendable (URLRequest) async throws -> (HTTPURLResponse, Data))?

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        loadingTask = Task {
            do {
                let (response, data) = try await handler(request)
                guard Task.isCancelled == false else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard Task.isCancelled == false else { return }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
    }
}
