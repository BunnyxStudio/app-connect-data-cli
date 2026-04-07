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
import ACDCore

public struct FXLookupRequest: Hashable, Codable, Sendable {
    public var dateKey: String
    public var currencyCode: String

    public init(dateKey: String, currencyCode: String) {
        self.dateKey = dateKey
        self.currencyCode = currencyCode
    }

    public var recordKey: String {
        "\(dateKey)|\(currencyCode)"
    }
}

public enum FXRateServiceError: LocalizedError {
    case invalidURL
    case provider(String)
    case unresolvedRates([FXLookupRequest])

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build FX rate request."
        case .provider(let message):
            return message
        case .unresolvedRates(let requests):
            let preview = requests.prefix(4).map { "\($0.dateKey)/\($0.currencyCode)" }.joined(separator: ", ")
            return "Missing FX rates for \(requests.count) request(s): \(preview)"
        }
    }
}

private struct CachedFXRate: Codable {
    var requestDateKey: String
    var sourceDateKey: String
    var currencyCode: String
    var usdPerUnit: Double
    var fetchedAt: Date
}

public actor FXRateService {
    private let cacheURL: URL
    private let session: URLSession
    private let fileManager: FileManager
    private let baseURL = URL(string: "https://api.frankfurter.dev/v2/rates")!

    public init(cacheURL: URL, session: URLSession = .shared, fileManager: FileManager = .default) {
        self.cacheURL = cacheURL
        self.session = session
        self.fileManager = fileManager
    }

    public func resolveUSDRates(for requests: Set<FXLookupRequest>) async throws -> [FXLookupRequest: Double] {
        guard requests.isEmpty == false else { return [:] }

        var cached = try loadCache()
        var resolved: [FXLookupRequest: Double] = [:]
        var missingByDate: [String: Set<String>] = [:]

        for request in requests {
            let normalized = request.currencyCode.normalizedCurrencyCode
            if normalized == "USD" {
                resolved[request] = 1
                continue
            }
            if normalized.isUnknownCurrencyCode {
                resolved[request] = 0
                continue
            }
            let key = FXLookupRequest(dateKey: request.dateKey, currencyCode: normalized)
            if let existing = cached[key.recordKey], existing.usdPerUnit > 0 {
                resolved[request] = existing.usdPerUnit
                continue
            }
            missingByDate[request.dateKey, default: []].insert(normalized)
        }

        for (dateKey, currencies) in missingByDate {
            let fetched = try await fetchRates(dateKey: dateKey, currencies: Array(currencies))
            for (currency, payload) in fetched {
                let record = CachedFXRate(
                    requestDateKey: dateKey,
                    sourceDateKey: payload.sourceDateKey,
                    currencyCode: currency,
                    usdPerUnit: payload.usdPerUnit,
                    fetchedAt: Date()
                )
                cached["\(dateKey)|\(currency)"] = record
            }
        }

        try saveCache(cached)

        var unresolved: [FXLookupRequest] = []
        for request in requests {
            let key = FXLookupRequest(dateKey: request.dateKey, currencyCode: request.currencyCode.normalizedCurrencyCode)
            if let cachedRate = cached[key.recordKey], cachedRate.usdPerUnit > 0 {
                resolved[request] = cachedRate.usdPerUnit
            } else if resolved[request] == nil {
                unresolved.append(request)
            }
        }
        if unresolved.isEmpty == false {
            throw FXRateServiceError.unresolvedRates(unresolved)
        }
        return resolved
    }

    private func fetchRates(dateKey: String, currencies: [String]) async throws -> [String: FetchedFXRate] {
        guard currencies.isEmpty == false else { return [:] }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        // FX lookup only sends date and currency codes. It never includes the .p8 key,
        // JWT, vendor number, review text, or raw report contents.
        components?.queryItems = [
            URLQueryItem(name: "date", value: dateKey),
            URLQueryItem(name: "base", value: "USD"),
            URLQueryItem(name: "quotes", value: currencies.sorted().joined(separator: ","))
        ]
        guard let url = components?.url else {
            throw FXRateServiceError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        if let error = try? JSONDecoder().decode(FrankfurterErrorResponse.self, from: data) {
            throw FXRateServiceError.provider("FX provider error: \(error.message)")
        }

        let response = try JSONDecoder().decode([FrankfurterRateQuote].self, from: data)
        var result: [String: FetchedFXRate] = [:]
        for quote in response where quote.rate != 0 {
            result[quote.quote] = FetchedFXRate(
                sourceDateKey: quote.date,
                usdPerUnit: 1 / quote.rate
            )
        }
        return result
    }

    private func loadCache() throws -> [String: CachedFXRate] {
        guard fileManager.fileExists(atPath: cacheURL.path) else { return [:] }
        try LocalFileSecurity.validateOwnerOnlyFile(cacheURL, fileManager: fileManager)
        let data = try Data(contentsOf: cacheURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: CachedFXRate].self, from: data)
    }

    private func saveCache(_ cache: [String: CachedFXRate]) throws {
        let parent = cacheURL.deletingLastPathComponent()
        try LocalFileSecurity.ensurePrivateDirectory(parent, fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)
        try LocalFileSecurity.writePrivateData(data, to: cacheURL, fileManager: fileManager)
    }
}

private struct FetchedFXRate {
    var sourceDateKey: String
    var usdPerUnit: Double
}

private struct FrankfurterRateQuote: Decodable {
    var date: String
    var quote: String
    var rate: Double
}

private struct FrankfurterErrorResponse: Decodable {
    var message: String
}
