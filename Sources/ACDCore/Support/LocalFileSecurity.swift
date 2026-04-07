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

public enum LocalFileSecurityError: LocalizedError, Equatable, Sendable {
    case insecureFilePermissions(path: String, expectedCommand: String)
    case insecureDirectoryPermissions(path: String, expectedCommand: String)

    public var errorDescription: String? {
        switch self {
        case .insecureFilePermissions(let path, let expectedCommand):
            return "Refusing to use insecure file permissions at \(path). Restrict access to the current user only: \(expectedCommand)"
        case .insecureDirectoryPermissions(let path, let expectedCommand):
            return "Refusing to use insecure directory permissions at \(path). Restrict access to the current user only: \(expectedCommand)"
        }
    }
}

public enum LocalFileSecurity {
    public static func ensurePrivateDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: url.path) == false {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        try validateOwnerOnlyDirectory(url, fileManager: fileManager)
    }

    public static func writePrivateData(
        _ data: Data,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensurePrivateDirectory(url.deletingLastPathComponent(), fileManager: fileManager)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try validateOwnerOnlyFile(url, fileManager: fileManager)
    }

    public static func validateOwnerOnlyFileIfExists(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try validateOwnerOnlyFile(url, fileManager: fileManager)
    }

    public static func validateOwnerOnlyDirectoryIfExists(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try validateOwnerOnlyDirectory(url, fileManager: fileManager)
    }

    public static func validateOwnerOnlyFile(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard let permissions = try currentPermissions(for: url, fileManager: fileManager) else { return }
        if permissions & 0o077 != 0 {
            throw LocalFileSecurityError.insecureFilePermissions(
                path: url.path,
                expectedCommand: "chmod 600 '\(url.path)'"
            )
        }
    }

    public static func validateOwnerOnlyDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard let permissions = try currentPermissions(for: url, fileManager: fileManager) else { return }
        if permissions & 0o077 != 0 {
            throw LocalFileSecurityError.insecureDirectoryPermissions(
                path: url.path,
                expectedCommand: "chmod 700 '\(url.path)'"
            )
        }
    }

    private static func currentPermissions(
        for url: URL,
        fileManager: FileManager
    ) throws -> Int? {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let number = attributes[.posixPermissions] as? NSNumber {
            return number.intValue
        }
        return nil
    }
}
