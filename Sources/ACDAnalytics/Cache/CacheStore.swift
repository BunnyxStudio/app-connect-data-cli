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

public enum CacheStoreError: LocalizedError {
    case ambiguousLegacyReviewsCache
    case ambiguousScopedReviewsCache

    public var errorDescription: String? {
        switch self {
        case .ambiguousLegacyReviewsCache:
            return "Cached reviews mix legacy latest.json with vendor-scoped review caches for multiple accounts. Clear the reviews cache or resync before querying."
        case .ambiguousScopedReviewsCache:
            return "Cached reviews contain multiple vendor-scoped snapshots. Set vendorNumber or clear the reviews cache before querying."
        }
    }
}

public struct CachedReportRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var source: ReportSource
    public var reportType: String
    public var reportSubType: String
    public var reportDateKey: String
    public var vendorNumber: String
    public var appID: String?
    public var bundleID: String?
    public var queryHash: String
    public var filePath: String
    public var fetchedAt: Date

    public init(
        id: String,
        source: ReportSource,
        reportType: String,
        reportSubType: String,
        reportDateKey: String,
        vendorNumber: String,
        appID: String? = nil,
        bundleID: String? = nil,
        queryHash: String,
        filePath: String,
        fetchedAt: Date
    ) {
        self.id = id
        self.source = source
        self.reportType = reportType
        self.reportSubType = reportSubType
        self.reportDateKey = reportDateKey
        self.vendorNumber = vendorNumber
        self.appID = appID
        self.bundleID = bundleID
        self.queryHash = queryHash
        self.filePath = filePath
        self.fetchedAt = fetchedAt
    }
}

public struct CachedReviewsPayload: Codable, Sendable {
    public var fetchedAt: Date
    public var reviews: [ASCLatestReview]

    public init(fetchedAt: Date, reviews: [ASCLatestReview]) {
        self.fetchedAt = fetchedAt
        self.reviews = reviews
    }
}

public final class CacheStore: @unchecked Sendable {
    private let fileManager: FileManager
    public let rootDirectory: URL

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public var reportsDirectory: URL {
        rootDirectory.appendingPathComponent("reports", isDirectory: true)
    }

    public var reviewsDirectory: URL {
        rootDirectory.appendingPathComponent("reviews", isDirectory: true)
    }

    public var reviewsURL: URL {
        reviewsDirectory.appendingPathComponent("latest.json")
    }

    public func reviewsURL(vendorNumber: String?) -> URL {
        guard let vendorNumber = normalizedVendorNumber(vendorNumber) else {
            return reviewsURL
        }
        return reviewsDirectory.appendingPathComponent("latest-\(vendorNumber).json")
    }

    public var manifestURL: URL {
        rootDirectory.appendingPathComponent("manifest.json")
    }

    public var fxRatesURL: URL {
        rootDirectory.appendingPathComponent("fx-rates.json")
    }

    public func prepare() throws {
        // CacheStore only persists downloaded reports and reviews.
        // Credentials and .p8 contents are never written here.
        for url in [rootDirectory, reportsDirectory, reviewsDirectory] {
            try LocalFileSecurity.ensurePrivateDirectory(url, fileManager: fileManager)
        }
    }

    @discardableResult
    public func record(report: DownloadedReport, fetchedAt: Date = Date()) throws -> CachedReportRecord {
        try record(reports: [report], fetchedAt: fetchedAt)[0]
    }

    @discardableResult
    public func record(reports: [DownloadedReport], fetchedAt: Date = Date()) throws -> [CachedReportRecord] {
        guard reports.isEmpty == false else { return [] }
        try prepare()
        var manifest = try loadManifest()
        var byID = Dictionary(uniqueKeysWithValues: manifest.map { ($0.id, $0) })
        var recorded: [CachedReportRecord] = []
        recorded.reserveCapacity(reports.count)

        for report in reports {
            let id = [
                report.source.rawValue,
                report.reportType,
                report.reportSubType,
                report.reportDateKey,
                report.vendorNumber,
                report.queryHash
            ].joined(separator: "|")
            let record = CachedReportRecord(
                id: id,
                source: report.source,
                reportType: report.reportType,
                reportSubType: report.reportSubType,
                reportDateKey: report.reportDateKey,
                vendorNumber: report.vendorNumber,
                appID: report.appID,
                bundleID: report.bundleID,
                queryHash: report.queryHash,
                filePath: report.fileURL.path,
                fetchedAt: fetchedAt
            )
            byID[record.id] = record
            recorded.append(record)
        }

        manifest = Array(byID.values)
        manifest.sort { lhs, rhs in
            if lhs.source == rhs.source {
                return lhs.reportDateKey < rhs.reportDateKey
            }
            return lhs.source.rawValue < rhs.source.rawValue
        }
        try saveManifest(manifest)
        return recorded
    }

    public func loadManifest() throws -> [CachedReportRecord] {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        try LocalFileSecurity.validateOwnerOnlyFile(manifestURL, fileManager: fileManager)
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder.iso8601.decode([CachedReportRecord].self, from: data)
    }

    public func saveReviews(_ payload: CachedReviewsPayload, vendorNumber: String? = nil) throws {
        try prepare()
        let data = try JSONEncoder.pretty.encode(payload)
        try LocalFileSecurity.writePrivateData(data, to: reviewsURL(vendorNumber: vendorNumber), fileManager: fileManager)
    }

    public func loadReviews(vendorNumber: String? = nil) throws -> CachedReviewsPayload? {
        for url in try reviewLoadCandidates(vendorNumber: vendorNumber) {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try LocalFileSecurity.validateOwnerOnlyFile(url, fileManager: fileManager)
            let data = try Data(contentsOf: url)
            return try JSONDecoder.iso8601.decode(CachedReviewsPayload.self, from: data)
        }
        return nil
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.removeItem(at: rootDirectory)
    }

    private func saveManifest(_ manifest: [CachedReportRecord]) throws {
        let data = try JSONEncoder.pretty.encode(manifest)
        try LocalFileSecurity.writePrivateData(data, to: manifestURL, fileManager: fileManager)
    }

    private func normalizedVendorNumber(_ vendorNumber: String?) -> String? {
        guard let vendorNumber else { return nil }
        let trimmed = vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func reviewLoadCandidates(vendorNumber: String?) throws -> [URL] {
        guard normalizedVendorNumber(vendorNumber) != nil else {
            let scopedURLs = (((try? fileManager.contentsOfDirectory(at: reviewsDirectory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("latest-") && $0.pathExtension == "json" })
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if fileManager.fileExists(atPath: reviewsURL.path) {
                if scopedURLs.isEmpty {
                    return [reviewsURL]
                }
                throw CacheStoreError.ambiguousLegacyReviewsCache
            }
            if scopedURLs.count > 1 {
                throw CacheStoreError.ambiguousScopedReviewsCache
            }
            return scopedURLs
        }

        let scopedURL = reviewsURL(vendorNumber: vendorNumber)
        if fileManager.fileExists(atPath: scopedURL.path) {
            return [scopedURL]
        }

        guard fileManager.fileExists(atPath: reviewsURL.path) else {
            return [scopedURL]
        }

        let hasScopedReviewCaches = ((try? fileManager.contentsOfDirectory(atPath: reviewsDirectory.path)) ?? []).contains {
            $0.hasPrefix("latest-") && $0.hasSuffix(".json")
        }
        if hasScopedReviewCaches {
            throw CacheStoreError.ambiguousLegacyReviewsCache
        }
        return [scopedURL, reviewsURL]
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
