import XCTest
import Foundation
@testable import ACDAnalytics
@testable import ACDCore

final class CacheStoreTests: XCTestCase {
    func testRecordReportsBatchDeduplicatesByLatestRecord() throws {
        let cacheStore = try makeCacheStore()
        let firstURL = cacheStore.reportsDirectory.appendingPathComponent("first.tsv")
        let secondURL = cacheStore.reportsDirectory.appendingPathComponent("second.tsv")
        let thirdURL = cacheStore.reportsDirectory.appendingPathComponent("third.tsv")
        try LocalFileSecurity.writePrivateData(Data("first".utf8), to: firstURL)
        try LocalFileSecurity.writePrivateData(Data("second".utf8), to: secondURL)
        try LocalFileSecurity.writePrivateData(Data("third".utf8), to: thirdURL)

        let reports = [
            DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY",
                queryHash: "duplicate",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: firstURL,
                rawText: "first"
            ),
            DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY",
                queryHash: "duplicate",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: secondURL,
                rawText: "second"
            ),
            DownloadedReport(
                source: .sales,
                reportType: "SUBSCRIPTION",
                reportSubType: "SUMMARY",
                queryHash: "unique",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: thirdURL,
                rawText: "third"
            )
        ]

        let recorded = try cacheStore.record(reports: reports)
        let manifest = try cacheStore.loadManifest()

        XCTAssertEqual(recorded.count, 3)
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(
            manifest.first(where: { $0.queryHash == "duplicate" })?.filePath,
            secondURL.path
        )
    }

    func testRecordReportsBatchKeepsDifferentVendorsSeparate() throws {
        let cacheStore = try makeCacheStore()
        let firstURL = cacheStore.reportsDirectory.appendingPathComponent("first.tsv")
        let secondURL = cacheStore.reportsDirectory.appendingPathComponent("second.tsv")
        try LocalFileSecurity.writePrivateData(Data("first".utf8), to: firstURL)
        try LocalFileSecurity.writePrivateData(Data("second".utf8), to: secondURL)

        _ = try cacheStore.record(reports: [
            DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY",
                queryHash: "duplicate",
                reportDateKey: "2026-02-18",
                vendorNumber: "VENDOR_A",
                fileURL: firstURL,
                rawText: "first"
            ),
            DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY",
                queryHash: "duplicate",
                reportDateKey: "2026-02-18",
                vendorNumber: "VENDOR_B",
                fileURL: secondURL,
                rawText: "second"
            )
        ])

        let manifest = try cacheStore.loadManifest()
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(Set(manifest.map(\.vendorNumber)), ["VENDOR_A", "VENDOR_B"])
    }

    func testReviewsAreStoredPerVendor() throws {
        let cacheStore = try makeCacheStore()
        let firstPayload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 1), reviews: [])
        let secondPayload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 2), reviews: [])

        try cacheStore.saveReviews(firstPayload, vendorNumber: "VENDOR_A")
        try cacheStore.saveReviews(secondPayload, vendorNumber: "VENDOR_B")

        XCTAssertEqual(try cacheStore.loadReviews(vendorNumber: "VENDOR_A")?.fetchedAt, firstPayload.fetchedAt)
        XCTAssertEqual(try cacheStore.loadReviews(vendorNumber: "VENDOR_B")?.fetchedAt, secondPayload.fetchedAt)
        XCTAssertThrowsError(try cacheStore.loadReviews()) { error in
            XCTAssertEqual(
                (error as? CacheStoreError)?.errorDescription,
                CacheStoreError.ambiguousScopedReviewsCache.errorDescription
            )
        }
    }

    func testLoadReviewsWithoutVendorFallsBackToSingleScopedCache() throws {
        let cacheStore = try makeCacheStore()
        let payload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 5), reviews: [])

        try cacheStore.saveReviews(payload, vendorNumber: "VENDOR_A")

        XCTAssertEqual(try cacheStore.loadReviews()?.fetchedAt, payload.fetchedAt)
    }

    func testLoadReviewsWithoutVendorRejectsMultipleScopedCaches() throws {
        let cacheStore = try makeCacheStore()

        try cacheStore.saveReviews(CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 1), reviews: []), vendorNumber: "VENDOR_A")
        try cacheStore.saveReviews(CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 2), reviews: []), vendorNumber: "VENDOR_B")

        XCTAssertThrowsError(try cacheStore.loadReviews()) { error in
            XCTAssertEqual(
                (error as? CacheStoreError)?.errorDescription,
                CacheStoreError.ambiguousScopedReviewsCache.errorDescription
            )
        }
    }

    func testLoadReviewsWithoutVendorRejectsLegacyCacheWhenScopedCacheExists() throws {
        let cacheStore = try makeCacheStore()
        let legacyPayload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 3), reviews: [])
        let scopedPayload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 4), reviews: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try LocalFileSecurity.writePrivateData(try encoder.encode(legacyPayload), to: cacheStore.reviewsURL)
        try cacheStore.saveReviews(scopedPayload, vendorNumber: "VENDOR_A")

        XCTAssertThrowsError(try cacheStore.loadReviews()) { error in
            XCTAssertEqual(
                (error as? CacheStoreError)?.errorDescription,
                CacheStoreError.ambiguousLegacyReviewsCache.errorDescription
            )
        }
    }

    func testLoadReviewsFallsBackToLegacyCacheWhenScopedCacheIsMissing() throws {
        let cacheStore = try makeCacheStore()
        let payload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 3), reviews: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try LocalFileSecurity.writePrivateData(try encoder.encode(payload), to: cacheStore.reviewsURL)

        XCTAssertEqual(try cacheStore.loadReviews(vendorNumber: "VENDOR_A")?.fetchedAt, payload.fetchedAt)
    }

    func testLoadReviewsRejectsAmbiguousLegacyCacheWhenScopedFilesExist() throws {
        let cacheStore = try makeCacheStore()
        let legacyPayload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 3), reviews: [])
        let scopedPayload = CachedReviewsPayload(fetchedAt: Date(timeIntervalSince1970: 4), reviews: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try LocalFileSecurity.writePrivateData(try encoder.encode(legacyPayload), to: cacheStore.reviewsURL)
        try cacheStore.saveReviews(scopedPayload, vendorNumber: "VENDOR_B")

        XCTAssertThrowsError(try cacheStore.loadReviews(vendorNumber: "VENDOR_A")) { error in
            XCTAssertEqual(
                (error as? CacheStoreError)?.errorDescription,
                CacheStoreError.ambiguousLegacyReviewsCache.errorDescription
            )
        }
    }

    private func makeCacheStore() throws -> CacheStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()
        return cacheStore
    }
}
