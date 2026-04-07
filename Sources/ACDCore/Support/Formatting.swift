//
//  Formatting.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import CryptoKit
import Foundation

public extension String {
    func maskMiddle(prefix: Int = 3, suffix: Int = 3) -> String {
        guard count > prefix + suffix else { return self }
        let start = self[startIndex..<index(startIndex, offsetBy: prefix)]
        let end = self[index(endIndex, offsetBy: -suffix)..<endIndex]
        return "\(start)***\(end)"
    }

    nonisolated var sha256Hex: String {
        let data = Data(utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated var normalizedCurrencyCode: String {
        let cleaned = trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.isEmpty || cleaned == "-" {
            return "UNK"
        }
        if cleaned == "UNKNOWN" {
            return "UNK"
        }
        return cleaned
    }

    nonisolated var isUnknownCurrencyCode: Bool {
        normalizedCurrencyCode == "UNK"
    }
}
