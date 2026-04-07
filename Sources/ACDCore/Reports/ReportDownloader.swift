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

//
//  ReportDownloader.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import Foundation

public enum ReportDownloaderError: Error {
    case missingCredentials
    case invalidText
    case decompressionFailed
}

public final class ReportDownloader: ReportDownloaderProtocol {
    private let fileManager: FileManager
    private let client: ASCClientProtocol
    private let credentialsProvider: () throws -> Credentials
    private let reportsRootDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        client: ASCClientProtocol,
        credentialsProvider: @escaping () throws -> Credentials,
        reportsRootDirectoryURL: URL
    ) {
        self.fileManager = fileManager
        self.client = client
        self.credentialsProvider = credentialsProvider
        self.reportsRootDirectoryURL = reportsRootDirectoryURL
    }

    public func fetchSalesReport(
        query: SalesReportQuery,
        reportDateKey: String,
        cachePolicy: ReportCachePolicy
    ) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let queryHash = query.canonicalQuery.sha256Hex
        return try await fetch(
            source: .sales,
            reportType: query.reportType,
            reportSubType: query.reportSubType,
            reportDateKey: reportDateKey,
            queryHash: queryHash,
            vendorNumber: credentials.vendorNumber,
            cachePolicy: cachePolicy
        ) {
            try await client.downloadSalesReport(query: query)
        }
    }

    public func fetchSalesDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let dateKey = datePT?.ptDateString ?? "latest"
        let query = SalesReportQuery.summarySales(
            vendorNumber: credentials.vendorNumber,
            reportDate: datePT?.ptDateString
        )
        return try await fetchSalesReport(query: query, reportDateKey: dateKey, cachePolicy: cachePolicy)
    }

    public func fetchSalesMonthly(fiscalMonth: String, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let query = SalesReportQuery.summarySalesMonthly(
            vendorNumber: credentials.vendorNumber,
            fiscalMonth: fiscalMonth
        )
        var report = try await fetchSalesReport(
            query: query,
            reportDateKey: fiscalMonth,
            cachePolicy: cachePolicy
        )
        // Keep API filter as SALES/SUMMARY but tag local rows as monthly summary coverage.
        report.reportSubType = "SUMMARY_MONTHLY"
        return report
    }

    public func fetchSubscriptionDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let dateKey = datePT?.ptDateString ?? "latest"
        let query = SalesReportQuery.subscriptionDaily(
            vendorNumber: credentials.vendorNumber,
            reportDate: datePT?.ptDateString
        )
        return try await fetchSalesReport(query: query, reportDateKey: dateKey, cachePolicy: cachePolicy)
    }

    public func fetchSubscriptionEventDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let dateKey = datePT?.ptDateString ?? "latest"
        let query = SalesReportQuery.subscriptionEventDaily(
            vendorNumber: credentials.vendorNumber,
            reportDate: datePT?.ptDateString
        )
        return try await fetchSalesReport(query: query, reportDateKey: dateKey, cachePolicy: cachePolicy)
    }

    public func fetchSubscriberDaily(datePT: Date?, cachePolicy: ReportCachePolicy) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let dateKey = datePT?.ptDateString ?? "latest"
        let query = SalesReportQuery.subscriberDaily(
            vendorNumber: credentials.vendorNumber,
            reportDate: datePT?.ptDateString
        )
        return try await fetchSalesReport(query: query, reportDateKey: dateKey, cachePolicy: cachePolicy)
    }

    public func fetchFinanceMonth(
        fiscalMonth: String,
        reportType: FinanceReportType,
        regionCode: String,
        cachePolicy: ReportCachePolicy
    ) async throws -> DownloadedReport {
        let credentials = try credentialsProvider()
        let reportDateKey = "\(fiscalMonth)-\(reportType.rawValue)-\(regionCode)"
        let query = FinanceReportQuery(
            reportType: reportType,
            regionCode: regionCode,
            reportDate: fiscalMonth,
            vendorNumber: credentials.vendorNumber
        )
        let queryHash = query.canonicalQuery.sha256Hex
        return try await fetch(
            source: .finance,
            reportType: reportType.rawValue,
            reportSubType: regionCode,
            reportDateKey: reportDateKey,
            queryHash: queryHash,
            vendorNumber: credentials.vendorNumber,
            cachePolicy: cachePolicy
        ) {
            try await client.downloadFinanceReport(query: query)
        }
    }

    public func clearDiskCache() throws {
        let reportsDirectory = try reportsRootDirectory()
        if fileManager.fileExists(atPath: reportsDirectory.path) {
            try fileManager.removeItem(at: reportsDirectory)
        }
    }

    private func fetch(
        source: ReportSource,
        reportType: String,
        reportSubType: String,
        reportDateKey: String,
        queryHash: String,
        vendorNumber: String,
        cachePolicy: ReportCachePolicy,
        download: () async throws -> Data
    ) async throws -> DownloadedReport {
        let folderURL = try folder(for: source, dateKey: reportDateKey)
        let textURL = folderURL.appendingPathComponent("\(queryHash).txt")
        let gzipURL = folderURL.appendingPathComponent("\(queryHash).gz")

        if cachePolicy == .useCached,
           fileManager.fileExists(atPath: textURL.path),
           (try? LocalFileSecurity.validateOwnerOnlyFile(textURL, fileManager: fileManager)) != nil,
           let text = try? String(contentsOf: textURL, encoding: .utf8) {
            return DownloadedReport(
                source: source,
                reportType: reportType,
                reportSubType: reportSubType,
                queryHash: queryHash,
                reportDateKey: reportDateKey,
                vendorNumber: vendorNumber,
                fileURL: textURL,
                rawText: text
            )
        }

        let data: Data
        do {
            data = try await download()
        } catch {
            if cachePolicy == .useCached,
               fileManager.fileExists(atPath: textURL.path),
               (try? LocalFileSecurity.validateOwnerOnlyFile(textURL, fileManager: fileManager)) != nil,
               let text = try? String(contentsOf: textURL, encoding: .utf8) {
                return DownloadedReport(
                    source: source,
                    reportType: reportType,
                    reportSubType: reportSubType,
                    queryHash: queryHash,
                    reportDateKey: reportDateKey,
                    vendorNumber: vendorNumber,
                    fileURL: textURL,
                    rawText: text
                )
            }
            throw error
        }
        let textData: Data
        if data.isGzipData {
            textData = try data.gunzipped()
            try LocalFileSecurity.writePrivateData(data, to: gzipURL, fileManager: fileManager)
        } else {
            textData = data
        }

        guard let text = String(data: textData, encoding: .utf8) else {
            throw ReportDownloaderError.invalidText
        }

        try LocalFileSecurity.writePrivateData(textData, to: textURL, fileManager: fileManager)
        return DownloadedReport(
            source: source,
            reportType: reportType,
            reportSubType: reportSubType,
            queryHash: queryHash,
            reportDateKey: reportDateKey,
            vendorNumber: vendorNumber,
            fileURL: textURL,
            rawText: text
        )
    }

    private func reportsRootDirectory() throws -> URL {
        let root = reportsRootDirectoryURL
        try LocalFileSecurity.ensurePrivateDirectory(root, fileManager: fileManager)
        return root
    }

    private func folder(for source: ReportSource, dateKey: String) throws -> URL {
        let root = try reportsRootDirectory()
        let sourceFolder = root.appendingPathComponent(source.rawValue, isDirectory: true)
        try LocalFileSecurity.ensurePrivateDirectory(sourceFolder, fileManager: fileManager)
        let dateFolder = sourceFolder.appendingPathComponent(dateKey, isDirectory: true)
        try LocalFileSecurity.ensurePrivateDirectory(dateFolder, fileManager: fileManager)
        return dateFolder
    }
}
