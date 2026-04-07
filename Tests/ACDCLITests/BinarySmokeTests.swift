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

final class BinarySmokeTests: XCTestCase {
    func testHealthCommandRunsWithoutCredentials() throws {
        let workingDirectory = try makeTempDirectory()
        try FileManager.default.createDirectory(at: workingDirectory.appendingPathComponent(".app-connect-data-cli"), withIntermediateDirectories: true)

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("app-connect-data-cli")
        process.arguments = ["query", "health", "--output", "json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("\"confidence\""))
    }

    func testQueryRunFromStdinWorks() throws {
        let workingDirectory = try makeTempDirectory()
        try FileManager.default.createDirectory(at: workingDirectory.appendingPathComponent(".app-connect-data-cli"), withIntermediateDirectories: true)

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("app-connect-data-cli")
        process.arguments = ["query", "run", "--spec", "-", "--output", "json"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(Data(#"{"kind":"health","filters":{}}"#.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let rendered = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, rendered)
        XCTAssertTrue(rendered.contains("\"confidence\""))
    }

    func testSnapshotCommandAcceptsRangePreset() throws {
        let workingDirectory = try makeTempDirectory()
        try FileManager.default.createDirectory(at: workingDirectory.appendingPathComponent(".app-connect-data-cli"), withIntermediateDirectories: true)

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("app-connect-data-cli")
        process.arguments = ["query", "snapshot", "--range", "last-week", "--output", "json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("\"source\""))
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
        return url
    }
}
