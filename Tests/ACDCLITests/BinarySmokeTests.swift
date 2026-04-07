import XCTest
import Foundation

final class BinarySmokeTests: XCTestCase {
    func testHealthCommandRunsWithoutCredentials() throws {
        let workingDirectory = try makeTempDirectory()
        try FileManager.default.createDirectory(at: workingDirectory.appendingPathComponent(".acd"), withIntermediateDirectories: true)

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("acd")
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
        try FileManager.default.createDirectory(at: workingDirectory.appendingPathComponent(".acd"), withIntermediateDirectories: true)

        let process = Process()
        process.currentDirectoryURL = workingDirectory
        process.executableURL = productsDirectory.appendingPathComponent("acd")
        process.arguments = ["query", "run", "-", "--output", "json"]

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
