//
//  P8Importer.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import CryptoKit
import Foundation

public enum P8ImporterError: Error {
    case unreadable
    case invalidPEM
}

public struct P8Importer: P8ImporterProtocol {
    public init() {}

    public func loadPrivateKeyPEM(from url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url),
              let pem = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw P8ImporterError.unreadable
        }

        guard pem.contains("BEGIN PRIVATE KEY"), pem.contains("END PRIVATE KEY") else {
            throw P8ImporterError.invalidPEM
        }

        do {
            _ = try P256.Signing.PrivateKey(pemRepresentation: pem)
            return pem
        } catch {
            throw P8ImporterError.invalidPEM
        }
    }
}
