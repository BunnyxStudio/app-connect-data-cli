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
@testable import ACDCore

final class LocalFileSecurityTests: XCTestCase {
    func testWritePrivateDataCreatesOwnerOnlyFile() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("secret.txt")

        try LocalFileSecurity.writePrivateData(Data("secret".utf8), to: fileURL)

        let permissions = try permissionsForItem(at: fileURL)
        XCTAssertEqual(permissions & 0o077, 0)
    }

    func testValidateOwnerOnlyFileRejectsWorldReadableFile() throws {
        let directory = try makeTempDirectory()
        let fileURL = directory.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        XCTAssertThrowsError(try LocalFileSecurity.validateOwnerOnlyFile(fileURL)) { error in
            XCTAssertTrue((error as? LocalFileSecurityError)?.errorDescription?.contains("chmod 600") == true)
        }
    }

    func testValidateOwnerOnlyDirectoryRejectsWorldReadableDirectory() throws {
        let directory = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)

        XCTAssertThrowsError(try LocalFileSecurity.validateOwnerOnlyDirectory(directory)) { error in
            XCTAssertTrue((error as? LocalFileSecurityError)?.errorDescription?.contains("chmod 700") == true)
        }
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func permissionsForItem(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
