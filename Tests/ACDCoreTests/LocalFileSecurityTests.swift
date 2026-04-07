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
