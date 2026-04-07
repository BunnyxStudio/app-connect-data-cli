import Foundation
import ACDCore

public struct CachedReportRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var source: ReportSource
    public var reportType: String
    public var reportSubType: String
    public var reportDateKey: String
    public var vendorNumber: String
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

public final class CacheStore {
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

    public var manifestURL: URL {
        rootDirectory.appendingPathComponent("manifest.json")
    }

    public var fxCacheURL: URL {
        rootDirectory.appendingPathComponent("fx-rates.json")
    }

    public func prepare() throws {
        // CacheStore only persists downloaded reports, reviews, and FX metadata.
        // Credentials and .p8 contents are never written here.
        for url in [rootDirectory, reportsDirectory, reviewsDirectory] {
            try LocalFileSecurity.ensurePrivateDirectory(url, fileManager: fileManager)
        }
    }

    @discardableResult
    public func record(report: DownloadedReport, fetchedAt: Date = Date()) throws -> CachedReportRecord {
        try prepare()
        let id = [
            report.source.rawValue,
            report.reportType,
            report.reportSubType,
            report.reportDateKey,
            report.queryHash
        ].joined(separator: "|")
        let record = CachedReportRecord(
            id: id,
            source: report.source,
            reportType: report.reportType,
            reportSubType: report.reportSubType,
            reportDateKey: report.reportDateKey,
            vendorNumber: report.vendorNumber,
            queryHash: report.queryHash,
            filePath: report.fileURL.path,
            fetchedAt: fetchedAt
        )
        var manifest = try loadManifest()
        manifest.removeAll { $0.id == record.id }
        manifest.append(record)
        manifest.sort { lhs, rhs in
            if lhs.source == rhs.source {
                return lhs.reportDateKey < rhs.reportDateKey
            }
            return lhs.source.rawValue < rhs.source.rawValue
        }
        try saveManifest(manifest)
        return record
    }

    public func loadManifest() throws -> [CachedReportRecord] {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        try LocalFileSecurity.validateOwnerOnlyFile(manifestURL, fileManager: fileManager)
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder.iso8601.decode([CachedReportRecord].self, from: data)
    }

    public func saveReviews(_ payload: CachedReviewsPayload) throws {
        try prepare()
        let data = try JSONEncoder.pretty.encode(payload)
        try LocalFileSecurity.writePrivateData(data, to: reviewsURL, fileManager: fileManager)
    }

    public func loadReviews() throws -> CachedReviewsPayload? {
        guard fileManager.fileExists(atPath: reviewsURL.path) else { return nil }
        try LocalFileSecurity.validateOwnerOnlyFile(reviewsURL, fileManager: fileManager)
        let data = try Data(contentsOf: reviewsURL)
        return try JSONDecoder.iso8601.decode(CachedReviewsPayload.self, from: data)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.removeItem(at: rootDirectory)
    }

    private func saveManifest(_ manifest: [CachedReportRecord]) throws {
        let data = try JSONEncoder.pretty.encode(manifest)
        try LocalFileSecurity.writePrivateData(data, to: manifestURL, fileManager: fileManager)
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
