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

public let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current

public struct Credentials: Codable, Equatable, Sendable {
    public var issuerID: String
    public var keyID: String
    public var vendorNumber: String
    public var privateKeyPEM: String

    public init(
        issuerID: String,
        keyID: String,
        vendorNumber: String,
        privateKeyPEM: String
    ) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.vendorNumber = vendorNumber
        self.privateKeyPEM = privateKeyPEM
    }

    public var maskedIssuerID: String { issuerID.maskMiddle() }
    public var maskedKeyID: String { keyID.maskMiddle() }
    public var maskedVendorNumber: String { vendorNumber.maskMiddle() }
}

public enum FinanceReportType: String, Codable, CaseIterable, Sendable {
    case financial = "FINANCIAL"
    case financeDetail = "FINANCE_DETAIL"
}

public struct SalesReportQuery: Codable, Sendable, Equatable {
    public var frequency: String = "DAILY"
    public var reportType: String = "SALES"
    public var reportSubType: String = "SUMMARY"
    public var vendorNumber: String
    public var version: String = "1_0"
    public var reportDate: String?

    public init(
        frequency: String = "DAILY",
        reportType: String = "SALES",
        reportSubType: String = "SUMMARY",
        vendorNumber: String,
        version: String = "1_0",
        reportDate: String? = nil
    ) {
        self.frequency = frequency
        self.reportType = reportType
        self.reportSubType = reportSubType
        self.vendorNumber = vendorNumber
        self.version = version
        self.reportDate = reportDate
    }

    public var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "filter[frequency]", value: frequency),
            URLQueryItem(name: "filter[reportType]", value: reportType),
            URLQueryItem(name: "filter[reportSubType]", value: reportSubType),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber),
            URLQueryItem(name: "filter[version]", value: version)
        ]
        if let reportDate {
            items.append(URLQueryItem(name: "filter[reportDate]", value: reportDate))
        }
        return items.sorted(by: { $0.name < $1.name })
    }

    public var canonicalQuery: String {
        queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    public static func summarySales(vendorNumber: String, reportDate: String?) -> SalesReportQuery {
        SalesReportQuery(vendorNumber: vendorNumber, reportDate: reportDate)
    }

    public static func summarySalesMonthly(vendorNumber: String, fiscalMonth: String) -> SalesReportQuery {
        SalesReportQuery(
            frequency: "MONTHLY",
            reportType: "SALES",
            reportSubType: "SUMMARY",
            vendorNumber: vendorNumber,
            version: "1_0",
            reportDate: fiscalMonth
        )
    }

    public static func subscriptionDaily(vendorNumber: String, reportDate: String?) -> SalesReportQuery {
        SalesReportQuery(
            frequency: "DAILY",
            reportType: "SUBSCRIPTION",
            reportSubType: "SUMMARY",
            vendorNumber: vendorNumber,
            version: "1_3",
            reportDate: reportDate
        )
    }

    public static func subscriptionEventDaily(vendorNumber: String, reportDate: String?) -> SalesReportQuery {
        SalesReportQuery(
            frequency: "DAILY",
            reportType: "SUBSCRIPTION_EVENT",
            reportSubType: "SUMMARY",
            vendorNumber: vendorNumber,
            version: "1_3",
            reportDate: reportDate
        )
    }

    public static func subscriberDaily(vendorNumber: String, reportDate: String?) -> SalesReportQuery {
        SalesReportQuery(
            frequency: "DAILY",
            reportType: "SUBSCRIBER",
            reportSubType: "DETAILED",
            vendorNumber: vendorNumber,
            version: "1_3",
            reportDate: reportDate
        )
    }

    public static func preOrder(vendorNumber: String, reportDate: String?) -> SalesReportQuery {
        SalesReportQuery(
            frequency: "DAILY",
            reportType: "PRE_ORDER",
            reportSubType: "SUMMARY",
            vendorNumber: vendorNumber,
            version: "1_0",
            reportDate: reportDate
        )
    }

    public static func subscriptionOfferCodeRedemption(vendorNumber: String, reportDate: String?) -> SalesReportQuery {
        SalesReportQuery(
            frequency: "DAILY",
            reportType: "SUBSCRIPTION_OFFER_CODE_REDEMPTION",
            reportSubType: "SUMMARY",
            vendorNumber: vendorNumber,
            version: "1_0",
            reportDate: reportDate
        )
    }
}

public struct FinanceReportQuery: Codable, Sendable, Equatable {
    public var reportType: FinanceReportType
    public var regionCode: String
    public var reportDate: String
    public var vendorNumber: String

    public init(
        reportType: FinanceReportType,
        regionCode: String,
        reportDate: String,
        vendorNumber: String
    ) {
        self.reportType = reportType
        self.regionCode = regionCode
        self.reportDate = reportDate
        self.vendorNumber = vendorNumber
    }

    public var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "filter[regionCode]", value: regionCode),
            URLQueryItem(name: "filter[reportDate]", value: reportDate),
            URLQueryItem(name: "filter[reportType]", value: reportType.rawValue),
            URLQueryItem(name: "filter[vendorNumber]", value: vendorNumber)
        ]
        .sorted(by: { $0.name < $1.name })
    }

    public var canonicalQuery: String {
        queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }
}

public enum ReportSource: String, Codable, Sendable {
    case sales
    case finance
    case analytics
}

public enum ReportCachePolicy: String, Codable, Sendable {
    case useCached
    case reloadIgnoringCache
}

public struct DownloadedReport: Codable, Sendable {
    public var source: ReportSource
    public var reportType: String
    public var reportSubType: String
    public var queryHash: String
    public var reportDateKey: String
    public var vendorNumber: String
    public var appID: String?
    public var bundleID: String?
    public var fileURL: URL
    public var rawText: String

    public init(
        source: ReportSource,
        reportType: String,
        reportSubType: String,
        queryHash: String,
        reportDateKey: String,
        vendorNumber: String,
        appID: String? = nil,
        bundleID: String? = nil,
        fileURL: URL,
        rawText: String
    ) {
        self.source = source
        self.reportType = reportType
        self.reportSubType = reportSubType
        self.queryHash = queryHash
        self.reportDateKey = reportDateKey
        self.vendorNumber = vendorNumber
        self.appID = appID
        self.bundleID = bundleID
        self.fileURL = fileURL
        self.rawText = rawText
    }
}

public enum SetupValidationError: LocalizedError, Equatable, Sendable {
    case missingIssuer
    case missingKeyID
    case missingVendor
    case missingP8

    public var errorDescription: String? {
        switch self {
        case .missingIssuer:
            return "Issuer ID is required."
        case .missingKeyID:
            return "Key ID is required."
        case .missingVendor:
            return "Vendor Number is required."
        case .missingP8:
            return ".p8 private key is required."
        }
    }
}

public protocol P8ImporterProtocol {
    func loadPrivateKeyPEM(from url: URL) throws -> String
}

public protocol JWTSignerProtocol {
    func makeToken(credentials: Credentials, lifetimeSeconds: TimeInterval) throws -> String
}

public protocol ASCClientProtocol {
    func validateToken() async throws
    func downloadSalesReport(query: SalesReportQuery) async throws -> Data
    func downloadFinanceReport(query: FinanceReportQuery) async throws -> Data
    func listApps(limit: Int?) async throws -> [ASCAppSummary]
    func fetchLatestCustomerReviews(
        maxApps: Int?,
        perAppLimit: Int?,
        totalLimit: Int?,
        appPageLimit: Int,
        pageLimit: Int,
        query: ASCCustomerReviewQuery
    ) async throws -> [ASCLatestReview]
    func listAnalyticsReportRequests(appID: String) async throws -> [ASCAnalyticsReportRequest]
    func createAnalyticsReportRequest(
        appID: String,
        accessType: ASCAnalyticsAccessType
    ) async throws -> ASCAnalyticsReportRequest
    func listAnalyticsReports(
        requestID: String,
        category: ASCAnalyticsCategory?,
        name: String?
    ) async throws -> [ASCAnalyticsReport]
    func listAnalyticsReportInstances(
        reportID: String,
        granularity: ASCAnalyticsGranularity?,
        processingDate: String?
    ) async throws -> [ASCAnalyticsReportInstance]
    func listAnalyticsReportSegments(instanceID: String) async throws -> [ASCAnalyticsReportSegment]
    func download(url: URL) async throws -> Data
}

public protocol ReportDownloaderProtocol {
    func fetchSalesReport(query: SalesReportQuery, reportDateKey: String, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchSalesDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchSalesMonthly(fiscalMonth: String, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchSubscriptionDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchSubscriptionEventDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchSubscriberDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchPreOrderDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchSubscriptionOfferCodeRedemptionDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchFinanceMonth(fiscalMonth: String, reportType: FinanceReportType, regionCode: String, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport
    func fetchAnalyticsSegment(
        segment: ASCAnalyticsReportSegment,
        reportName: String,
        reportDateKey: String,
        cacheIdentity: String,
        appID: String,
        bundleID: String?,
        cachePolicy: ReportCachePolicy
    ) async throws -> DownloadedReport
    func clearDiskCache() throws
}
