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
@testable import ACDCore

final class BinarySmokeTests: XCTestCase {
    func testCapabilitiesListRunsWithoutCredentials() throws {
        let workingDirectory = try makeTempDirectory()
        let result = try runProcess(
            arguments: ["capabilities", "list", "--output", "table"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("sales"))
        XCTAssertTrue(result.output.contains("analytics"))
    }

    func testQueryRunFromStdinReadsCachedSalesData() throws {
        let workingDirectory = try makeTempDirectory()
        try seedSubscriptionCache(in: workingDirectory)

        let spec = DataQuerySpec(
            dataset: .sales,
            operation: .aggregate,
            time: QueryTimeSelection(datePT: "2026-02-18"),
            filters: QueryFilterSet(sourceReport: ["subscription"])
        )
        let input = try JSONEncoder().encode(spec)
        let result = try runProcess(
            arguments: ["query", "run", "--spec", "-", "--output", "json"],
            workingDirectory: workingDirectory,
            stdinData: input
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"dataset\" : \"sales\""))
        XCTAssertTrue(result.output.contains("\"subscribers\""))
    }

    func testSalesAggregateCommandUsesNewDirectQueryShape() throws {
        let workingDirectory = try makeTempDirectory()
        try seedSubscriptionCache(in: workingDirectory)

        let result = try runProcess(
            arguments: ["sales", "aggregate", "--date", "2026-02-18", "--source-report", "subscription", "--output", "table"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("activeSubscriptions"))
        XCTAssertTrue(result.output.contains("subscribers"))
    }

    func testBriefDailyRunsOfflineSummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "daily", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Daily Summary\""))
        XCTAssertTrue(result.output.contains("\"period\" : \"daily\""))
        XCTAssertTrue(result.output.contains("\"sections\""))
    }

    func testBriefWeeklyRunsWithoutConflictingTimeSelectors() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "weekly", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Week to Date Summary\""))
        XCTAssertTrue(result.output.contains("\"currentLabel\" : \"this week to date"))
        XCTAssertTrue(result.output.contains("\"Overview\""))
    }

    func testBriefMonthlyRunsOfflineSummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "monthly", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Month to Date Summary\""))
        XCTAssertTrue(result.output.contains("\"timeBasis\""))
        XCTAssertTrue(result.output.contains("\"Data Health\""))
    }

    func testBriefLastMonthRunsOfflineSummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["brief", "last-month", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"title\" : \"Last Month Summary\""))
        XCTAssertTrue(result.output.contains("\"period\" : \"last-month\""))
    }

    func testOverviewAliasRunsDailySummary() throws {
        let workingDirectory = try makeTempDirectory()

        let result = try runProcess(
            arguments: ["overview", "daily", "--offline", "--output", "json"],
            workingDirectory: workingDirectory
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"period\" : \"daily\""))
        XCTAssertTrue(result.output.contains("\"title\" : \"Daily Summary\""))
    }

    func testQueryRunBriefUsesBriefSummaryShape() throws {
        let workingDirectory = try makeTempDirectory()

        let spec = DataQuerySpec(
            dataset: .brief,
            operation: .brief,
            time: QueryTimeSelection(rangePreset: "this-week")
        )
        let input = try JSONEncoder().encode(spec)
        let result = try runProcess(
            arguments: ["query", "run", "--spec", "-", "--offline", "--output", "json"],
            workingDirectory: workingDirectory,
            stdinData: input
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("\"period\" : \"weekly\""))
        XCTAssertTrue(result.output.contains("\"sections\""))
        XCTAssertTrue(result.output.contains("\"timeBasis\""))
    }

    func testConfigCurrencySetWritesLocalReportingCurrency() throws {
        let workingDirectory = try makeTempDirectory()

        let setResult = try runProcess(
            arguments: ["config", "currency", "set", "CNY", "--local", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(setResult.status, 0, setResult.output)
        XCTAssertTrue(setResult.output.contains("\"reportingCurrency\" : \"CNY\""))

        let showResult = try runProcess(
            arguments: ["config", "currency", "show", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(showResult.status, 0, showResult.output)
        XCTAssertTrue(showResult.output.contains("\"reportingCurrency\" : \"CNY\""))
    }

    func testConfigTimezoneSetWritesLocalDisplayTimezone() throws {
        let workingDirectory = try makeTempDirectory()

        let setResult = try runProcess(
            arguments: ["config", "timezone", "set", "America/Los_Angeles", "--local", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(setResult.status, 0, setResult.output)
        XCTAssertTrue(setResult.output.contains("\"displayTimeZone\" : \"America\\/Los_Angeles\""))

        let showResult = try runProcess(
            arguments: ["config", "timezone", "show", "--output", "json"],
            workingDirectory: workingDirectory
        )
        XCTAssertEqual(showResult.status, 0, showResult.output)
        XCTAssertTrue(showResult.output.contains("\"displayTimeZone\" : \"America\\/Los_Angeles\""))
    }

    private func seedSubscriptionCache(in workingDirectory: URL) throws {
        let root = workingDirectory.appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()

        let text = try fixture(named: "subscription_2026-02-18.tsv")
        let fileURL = cacheStore.reportsDirectory.appendingPathComponent("subscription_2026-02-18.tsv")
        try LocalFileSecurity.writePrivateData(Data(text.utf8), to: fileURL)
        _ = try cacheStore.record(
            report: DownloadedReport(
                source: .sales,
                reportType: "SUBSCRIPTION",
                reportSubType: "SUMMARY",
                queryHash: "subscription_2026-02-18",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: fileURL,
                rawText: text
            )
        )
    }

    private func runProcess(
        arguments: [String],
        workingDirectory: URL,
        stdinData: Data? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("adc")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        if let stdinData {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(stdinData)
            try input.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        process.waitUntilExit()
        let rendered = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, rendered)
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("Missing products directory")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".app-connect-data-cli", isDirectory: true),
            withIntermediateDirectories: true
        )
        return url
    }

    private func fixture(named name: String) throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try String(contentsOf: path, encoding: .utf8)
    }
}
