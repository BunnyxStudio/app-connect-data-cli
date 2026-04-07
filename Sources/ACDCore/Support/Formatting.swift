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
