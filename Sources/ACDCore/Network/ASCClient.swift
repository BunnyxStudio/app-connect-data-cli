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
//  ASCClient.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import Foundation

actor ASCRequestGate {
    static let shared = ASCRequestGate(maxConcurrent: 3)

    private let maxConcurrent: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
            return
        }
        inFlight = max(0, inFlight - 1)
    }
}

public enum ASCClientError: LocalizedError {
    case missingCredentials
    case invalidURL
    case unauthorized(String?)
    case forbidden(String?)
    case rateLimited
    case teamKeyRequired
    case reportNotAvailableYet(String?)
    case httpStatus(Int, String?)
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing credentials."
        case .invalidURL:
            return "Invalid App Store Connect API URL."
        case .unauthorized(let message):
            return message ?? "Unauthorized (401)."
        case .forbidden(let message):
            return message ?? "Forbidden (403)."
        case .rateLimited:
            return "Rate limited (429)."
        case .teamKeyRequired:
            return "Sales and Finance endpoints require Team API key."
        case .reportNotAvailableYet(let message):
            return message ?? "Report is not available yet."
        case .httpStatus(let status, let message):
            return message ?? "Unexpected HTTP status \(status)."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

public struct ASCLatestReview: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var appID: String
    public var appName: String
    public var bundleID: String?
    public var rating: Int
    public var title: String
    public var body: String
    public var reviewerNickname: String
    public var territory: String?
    public var createdDate: Date
    public var developerResponse: ASCLatestReviewDeveloperResponse?
}

public struct ASCLatestReviewDeveloperResponse: Equatable, Codable, Sendable {
    public var id: String?
    public var body: String
    public var lastModifiedDate: Date?
    public var state: String?
}

public struct ASCRatingsSummary: Equatable, Codable, Sendable {
    public var totalCount: Int
    public var averageRating: Double
    public var starCounts: [Int: Int]

    public var normalizedStarCounts: [Int: Int] {
        var normalized: [Int: Int] = [:]
        for star in 1...5 {
            normalized[star] = max(0, starCounts[star] ?? 0)
        }
        return normalized
    }

    public var histogramCount: Int {
        normalizedStarCounts.values.reduce(0, +)
    }

    public static func fromReviews(_ reviews: [ASCLatestReview]) -> ASCRatingsSummary {
        guard reviews.isEmpty == false else {
            return ASCRatingsSummary(totalCount: 0, averageRating: 0, starCounts: [:])
        }
        let total = reviews.count
        let weighted = reviews.reduce(0) { $0 + max(1, min(5, $1.rating)) }
        let grouped = Dictionary(grouping: reviews, by: { max(1, min(5, $0.rating)) })
        let counts = grouped.mapValues(\.count)
        return ASCRatingsSummary(
            totalCount: total,
            averageRating: Double(weighted) / Double(total),
            starCounts: counts
        )
    }
}

public enum ASCCustomerReviewSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case ratingHigh
    case ratingLow

    public var id: String { rawValue }

    fileprivate var apiValue: String {
        switch self {
        case .newest:
            return "-createdDate"
        case .oldest:
            return "createdDate"
        case .ratingHigh:
            return "-rating"
        case .ratingLow:
            return "rating"
        }
    }
}

public struct ASCCustomerReviewQuery: Sendable {
    public var sort: ASCCustomerReviewSort = .newest
    public var ratings: Set<Int> = []
    public var territory: String?
    public var hasPublishedResponse: Bool?

    public nonisolated init(
        sort: ASCCustomerReviewSort = .newest,
        ratings: Set<Int> = [],
        territory: String? = nil,
        hasPublishedResponse: Bool? = nil
    ) {
        self.sort = sort
        self.ratings = ratings
        self.territory = territory
        self.hasPublishedResponse = hasPublishedResponse
    }

    public var normalizedRatings: [Int] {
        ratings.filter { (1...5).contains($0) }.sorted()
    }
}

public final class ASCClient: ASCClientProtocol {
    private let session: URLSession
    private let tokenProvider: () throws -> String
    private let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!
    private let iTunesLookupUserAgent = "Go-http-client/1.1"
    private let iTunesHistogramUserAgent = "iTunes/12.6.5 (Macintosh; OS X 10.13.4) AppleWebKit/604.5.6.1.1"
    private let iTunesHistogramMinimumRatings = 5
    private let iTunesRetryAttempts = 3
    private let maxRetryAttempts = 3
    private let requestTimeout: TimeInterval = 25
    private let retryBaseDelay: TimeInterval = 0.8

    private static let iTunesStorefrontByCountry: [String: String] = [
        "ae": "143481",
        "ai": "143538",
        "am": "143524",
        "ao": "143564",
        "ar": "143505",
        "at": "143445",
        "au": "143460",
        "az": "143568",
        "bb": "143541",
        "be": "143446",
        "bg": "143526",
        "bh": "143559",
        "bm": "143542",
        "bn": "143560",
        "bo": "143556",
        "br": "143503",
        "bw": "143525",
        "by": "143565",
        "bz": "143555",
        "ca": "143455",
        "ch": "143459",
        "cl": "143483",
        "cn": "143465",
        "co": "143501",
        "cr": "143495",
        "cy": "143557",
        "cz": "143489",
        "de": "143443",
        "dk": "143458",
        "dm": "143545",
        "dz": "143563",
        "ec": "143509",
        "ee": "143518",
        "eg": "143516",
        "es": "143454",
        "fi": "143447",
        "fr": "143442",
        "gb": "143444",
        "gd": "143546",
        "gh": "143573",
        "gr": "143448",
        "gt": "143504",
        "gy": "143553",
        "hk": "143463",
        "hn": "143510",
        "hr": "143494",
        "hu": "143482",
        "id": "143476",
        "ie": "143449",
        "il": "143491",
        "in": "143467",
        "is": "143558",
        "it": "143450",
        "jm": "143511",
        "jo": "143528",
        "jp": "143462",
        "ke": "143529",
        "kr": "143466",
        "kw": "143493",
        "ky": "143544",
        "lb": "143497",
        "lk": "143486",
        "lt": "143520",
        "lu": "143451",
        "lv": "143519",
        "mg": "143531",
        "mk": "143530",
        "ml": "143532",
        "mo": "143515",
        "ms": "143547",
        "mt": "143521",
        "mu": "143533",
        "mx": "143468",
        "my": "143473",
        "ne": "143534",
        "ng": "143561",
        "ni": "143512",
        "nl": "143452",
        "no": "143457",
        "np": "143484",
        "nz": "143461",
        "om": "143562",
        "pa": "143485",
        "pe": "143507",
        "ph": "143474",
        "pk": "143477",
        "pl": "143478",
        "pt": "143453",
        "py": "143513",
        "qa": "143498",
        "ro": "143487",
        "ru": "143469",
        "sa": "143479",
        "se": "143456",
        "sg": "143464",
        "si": "143499",
        "sk": "143496",
        "sn": "143535",
        "sr": "143554",
        "sv": "143506",
        "th": "143475",
        "tn": "143536",
        "tr": "143480",
        "tw": "143470",
        "tz": "143572",
        "ua": "143492",
        "ug": "143537",
        "us": "143441",
        "uy": "143514",
        "uz": "143566",
        "ve": "143502",
        "vg": "143543",
        "vn": "143471",
        "ye": "143571",
        "za": "143472",
    ]

    public init(
        session: URLSession = .shared,
        tokenProvider: @escaping () throws -> String
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    public convenience init(staticToken: String) {
        self.init(tokenProvider: { staticToken })
    }

    public func validateToken() async throws {
        _ = try await request(
            path: "/v1/apps",
            queryItems: [URLQueryItem(name: "limit", value: "1")]
        )
    }

    public func downloadSalesReport(query: SalesReportQuery) async throws -> Data {
        try await request(path: "/v1/salesReports", queryItems: query.queryItems)
    }

    public func downloadFinanceReport(query: FinanceReportQuery) async throws -> Data {
        try await request(path: "/v1/financeReports", queryItems: query.queryItems)
    }

    public func fetchRatingsSummary(
        appIDs: [String],
        territory: String? = nil,
        workerCount: Int = 8
    ) async -> ASCRatingsSummary? {
        let normalizedAppIDs = appIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard normalizedAppIDs.isEmpty == false else { return nil }

        var totalCount = 0
        var weightedRatingTotal = 0.0
        var mergedStarCounts: [Int: Int] = [:]

        for appID in normalizedAppIDs {
            guard let summary = await fetchRatingsSummaryForSingleApp(
                appID: appID,
                territory: territory,
                workerCount: workerCount
            ) else {
                continue
            }
            totalCount += summary.totalCount
            weightedRatingTotal += summary.averageRating * Double(summary.totalCount)
            for (star, count) in summary.normalizedStarCounts {
                mergedStarCounts[star, default: 0] += count
            }
        }

        guard totalCount > 0 || mergedStarCounts.isEmpty == false else { return nil }

        let averageRating = totalCount > 0 ? weightedRatingTotal / Double(totalCount) : 0
        return ASCRatingsSummary(
            totalCount: totalCount,
            averageRating: averageRating,
            starCounts: mergedStarCounts
        )
    }

    private func fetchRatingsSummaryForSingleApp(
        appID: String,
        territory: String?,
        workerCount: Int
    ) async -> ASCRatingsSummary? {
        let countries = ratingCountryCodes(for: territory)
        guard countries.isEmpty == false else { return nil }

        let cappedWorkers = max(1, min(workerCount, 20))
        var mergedByCountry = await fetchStorefrontRatings(
            appID: appID,
            countries: countries,
            workerCount: cappedWorkers
        )

        // The public iTunes endpoints are occasionally flaky per-country.
        // Retry only countries that likely need it to reduce overall latency.
        if territory == nil, countries.count > 1 {
            let retryCountries = countries.filter { countryCode in
                let key = countryCode.uppercased()
                guard let existing = mergedByCountry[key] else {
                    // Lookup failed or transient network issue on first pass.
                    return true
                }
                // Keep retrying large storefronts where histogram extraction failed.
                return existing.ratingCount >= iTunesHistogramMinimumRatings && existing.starCounts == nil
            }

            if retryCountries.isEmpty == false {
                let secondPass = await fetchStorefrontRatings(
                    appID: appID,
                    countries: retryCountries,
                    workerCount: max(1, cappedWorkers / 2)
                )
                for (country, candidate) in secondPass {
                    if let existing = mergedByCountry[country] {
                        mergedByCountry[country] = betterStorefrontRating(existing: existing, candidate: candidate)
                    } else {
                        mergedByCountry[country] = candidate
                    }
                }
            }
        }

        let storefrontRatings = mergedByCountry.values.filter { $0.ratingCount > 0 }
        guard storefrontRatings.isEmpty == false else { return nil }

        var totalCount = 0
        var weightedRatingTotal = 0.0
        var starCounts: [Int: Int] = [:]

        for storefront in storefrontRatings {
            totalCount += storefront.ratingCount
            weightedRatingTotal += storefront.averageRating * Double(storefront.ratingCount)
            if let histogram = storefront.starCounts {
                for (star, count) in histogram {
                    starCounts[star, default: 0] += count
                }
            }
        }

        guard totalCount > 0 else { return nil }

        return ASCRatingsSummary(
            totalCount: totalCount,
            averageRating: weightedRatingTotal / Double(totalCount),
            starCounts: starCounts
        )
    }

    private func fetchStorefrontRatings(
        appID: String,
        countries: [String],
        workerCount: Int
    ) async -> [String: ITunesStorefrontRating] {
        var byCountry: [String: ITunesStorefrontRating] = [:]
        byCountry.reserveCapacity(countries.count)

        var start = 0
        while start < countries.count {
            let end = min(start + max(1, workerCount), countries.count)
            let chunk = countries[start..<end]
            for country in chunk {
                if let rating = await fetchStorefrontRating(appID: appID, countryCode: country) {
                    byCountry[rating.countryCode] = rating
                }
            }
            start = end
        }

        return byCountry
    }

    private func betterStorefrontRating(
        existing: ITunesStorefrontRating,
        candidate: ITunesStorefrontRating
    ) -> ITunesStorefrontRating {
        if candidate.ratingCount > existing.ratingCount {
            return candidate
        }
        if candidate.ratingCount < existing.ratingCount {
            return existing
        }

        let existingHistogramCount = existing.starCounts?.values.reduce(0, +) ?? 0
        let candidateHistogramCount = candidate.starCounts?.values.reduce(0, +) ?? 0
        if candidateHistogramCount > existingHistogramCount {
            return candidate
        }
        return existing
    }

    private func fetchStorefrontRating(appID: String, countryCode: String) async -> ITunesStorefrontRating? {
        guard let lookupURL = makeITunesLookupURL(appID: appID, countryCode: countryCode) else {
            return nil
        }

        let lookupData: Data
        do {
            lookupData = try await requestITunes(url: lookupURL, userAgent: iTunesLookupUserAgent)
        } catch {
            return nil
        }

        let lookupResponse: ITunesLookupResponse
        do {
            lookupResponse = try JSONDecoder().decode(ITunesLookupResponse.self, from: lookupData)
        } catch {
            return nil
        }

        guard let appIDInt = Int(appID) else { return nil }
        let matched = lookupResponse.results.first { result in
            guard let trackID = result.trackId else { return false }
            return trackID == appIDInt
        } ?? lookupResponse.results.first

        guard let matched else {
            return ITunesStorefrontRating(
                countryCode: countryCode.uppercased(),
                ratingCount: 0,
                averageRating: 0,
                starCounts: nil
            )
        }

        let ratingCount = max(0, matched.userRatingCount ?? 0)
        let averageRating = max(0, matched.averageUserRating ?? 0)
        guard ratingCount >= iTunesHistogramMinimumRatings else {
            return ITunesStorefrontRating(
                countryCode: countryCode.uppercased(),
                ratingCount: ratingCount,
                averageRating: averageRating,
                starCounts: nil
            )
        }
        let starCounts = await fetchHistogramCounts(appID: appID, countryCode: countryCode)

        return ITunesStorefrontRating(
            countryCode: countryCode.uppercased(),
            ratingCount: ratingCount,
            averageRating: averageRating,
            starCounts: starCounts
        )
    }

    private func ratingCountryCodes(for territory: String?) -> [String] {
        if let territory {
            let normalized = territory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.count == 2, normalized.allSatisfy(\.isLetter) {
                return [normalized]
            }
        }

        return Self.iTunesStorefrontByCountry.keys.sorted()
    }

    private func fetchHistogramCounts(appID: String, countryCode: String) async -> [Int: Int]? {
        guard let reviewsURL = makeITunesCustomerReviewsURL(appID: appID, countryCode: countryCode) else {
            return nil
        }

        var extraHeaders: [String: String] = [:]
        if let storefront = Self.iTunesStorefrontByCountry[countryCode.lowercased()] {
            extraHeaders["X-Apple-Store-Front"] = "\(storefront),12"
        }

        let reviewData: Data
        do {
            reviewData = try await requestITunes(
                url: reviewsURL,
                userAgent: iTunesHistogramUserAgent,
                extraHeaders: extraHeaders,
                acceptHeader: nil
            )
        } catch {
            return nil
        }

        return parseHistogramCounts(from: reviewData)
    }

    private func parseHistogramCounts(from data: Data) -> [Int: Int]? {
        if let jsonResponse = try? JSONDecoder().decode(ITunesCustomerReviewsResponse.self, from: data),
           let ratingList = jsonResponse.ratingCountList,
           ratingList.count >= 5 {
            let counts = [
                1: max(0, ratingList[0]),
                2: max(0, ratingList[1]),
                3: max(0, ratingList[2]),
                4: max(0, ratingList[3]),
                5: max(0, ratingList[4]),
            ]
            if counts.values.reduce(0, +) > 0 {
                return counts
            }
        }

        guard let html = String(data: data, encoding: .utf8), html.isEmpty == false else {
            return nil
        }

        let pattern = #"<span[^>]*class=['"]total['"][^>]*>\s*([0-9,]+)\s*</span>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)

        let stars = [5, 4, 3, 2, 1]
        var counts: [Int: Int] = [:]

        for (index, star) in stars.enumerated() where index < matches.count {
            let match = matches[index]
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            let raw = html[valueRange].replacingOccurrences(of: ",", with: "")
            if let value = Int(raw), value >= 0 {
                counts[star] = value
            }
        }

        if counts.isEmpty == false {
            return counts
        }

        return parseReviewStarCounts(from: html)
    }

    private func parseReviewStarCounts(from html: String) -> [Int: Int]? {
        // Fallback for storefronts where Apple omits histogram totals but still renders
        // individual review cards with a localized aria-label that starts with a digit.
        let pattern = #"<div[^>]*class=['"]rating['"][^>]*aria-label=['"]\s*([1-5])[^'"]*['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        guard matches.isEmpty == false else {
            return nil
        }

        var counts: [Int: Int] = [:]
        for match in matches {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: html),
                  let star = Int(html[valueRange]),
                  (1...5).contains(star)
            else {
                continue
            }
            counts[star, default: 0] += 1
        }

        return counts.isEmpty ? nil : counts
    }

    private func makeITunesLookupURL(appID: String, countryCode: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: appID),
            URLQueryItem(name: "country", value: countryCode),
            URLQueryItem(name: "entity", value: "software"),
        ]
        return components?.url
    }

    private func makeITunesCustomerReviewsURL(appID: String, countryCode: String) -> URL? {
        URL(string: "https://itunes.apple.com/\(countryCode)/customer-reviews/id\(appID)?displayable-kind=11")
    }

    public func fetchLatestCustomerReviews(
        maxApps: Int? = nil,
        perAppLimit: Int? = nil,
        totalLimit: Int? = nil,
        appPageLimit: Int = 200,
        pageLimit: Int = 200,
        query: ASCCustomerReviewQuery = ASCCustomerReviewQuery()
    ) async throws -> [ASCLatestReview] {
        let cappedAppPageLimit = min(max(appPageLimit, 1), 200)
        let cappedPageLimit = min(max(pageLimit, 1), 200)
        let normalizedMaxApps = maxApps.map { max($0, 1) }
        let normalizedPerAppLimit = perAppLimit.map { max($0, 1) }
        let normalizedTotalLimit = totalLimit.map { max($0, 1) }
        let normalizedRatings = query.normalizedRatings
        let normalizedTerritory = normalize(query.territory)
        let decoder = JSONDecoder()
        var apps: [ASCResolvedApp] = []
        var visitedAppPageURLs: Set<String> = []
        var appPageURL = makeURL(
            path: "/v1/apps",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(cappedAppPageLimit)"),
                URLQueryItem(name: "fields[apps]", value: "name,bundleId")
            ]
        )

        while let currentAppPageURL = appPageURL {
            if visitedAppPageURLs.insert(currentAppPageURL.absoluteString).inserted == false {
                break
            }
            let appData = try await request(url: currentAppPageURL)
            let appsResponse = try decoder.decode(ASCCollectionResponse<ASCAppResource>.self, from: appData)
            var mapped = appsResponse.data.map {
                ASCResolvedApp(
                    id: $0.id,
                    name: ($0.attributes?.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown App",
                    bundleID: ($0.attributes?.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                )
            }

            if let maxApps = normalizedMaxApps {
                let remaining = maxApps - apps.count
                if remaining <= 0 {
                    break
                }
                if mapped.count > remaining {
                    mapped = Array(mapped.prefix(remaining))
                }
            }
            apps.append(contentsOf: mapped)

            if let maxApps = normalizedMaxApps, apps.count >= maxApps {
                break
            }

            if let nextLink = normalize(appsResponse.links?.next),
               let nextPageURL = URL(string: nextLink, relativeTo: baseURL)?.absoluteURL {
                appPageURL = nextPageURL
            } else {
                appPageURL = nil
            }
        }

        guard apps.isEmpty == false else { return [] }

        var merged: [ASCLatestReview] = []
        var firstFailure: Error?

        for app in apps {
            do {
                var reviewItems = [
                    URLQueryItem(name: "sort", value: query.sort.apiValue),
                    URLQueryItem(name: "limit", value: "\(cappedPageLimit)"),
                    URLQueryItem(
                        name: "fields[customerReviews]",
                        value: "rating,title,body,reviewerNickname,territory,createdDate,response"
                    ),
                    URLQueryItem(name: "include", value: "response"),
                    URLQueryItem(
                        name: "fields[customerReviewResponses]",
                        value: "responseBody,lastModifiedDate,state"
                    )
                ]
                if normalizedRatings.isEmpty == false {
                    let raw = normalizedRatings.map(String.init).joined(separator: ",")
                    reviewItems.append(URLQueryItem(name: "filter[rating]", value: raw))
                }
                if let normalizedTerritory {
                    reviewItems.append(URLQueryItem(name: "filter[territory]", value: normalizedTerritory))
                }
                if let hasPublishedResponse = query.hasPublishedResponse {
                    reviewItems.append(
                        URLQueryItem(
                            name: "exists[publishedResponse]",
                            value: hasPublishedResponse ? "true" : "false"
                        )
                    )
                }
                guard let firstPageURL = makeURL(path: "/v1/apps/\(app.id)/customerReviews", queryItems: reviewItems) else {
                    throw ASCClientError.invalidURL
                }

                var fetchedForApp = 0
                var pageURL: URL? = firstPageURL
                var visitedPageURLs: Set<String> = []

                while let currentPageURL = pageURL {
                    if visitedPageURLs.insert(currentPageURL.absoluteString).inserted == false {
                        break
                    }

                    let reviewData = try await request(url: currentPageURL)
                    let reviewResponse = try decoder.decode(
                        ASCCollectionResponse<ASCCustomerReviewResource>.self,
                        from: reviewData
                    )
                    let responsesByID = buildReviewResponseMap(included: reviewResponse.included)
                    var mapped = reviewResponse.data.compactMap { review -> ASCLatestReview? in
                        guard let attributes = review.attributes else { return nil }
                        guard let createdDate = parseASCDate(attributes.createdDate) else { return nil }
                        let rating = min(max(attributes.rating ?? 0, 0), 5)
                        guard rating > 0 else { return nil }
                        let responseID = review.relationships?.response?.data?.id
                        let developerResponse = responseID.flatMap { responsesByID[$0] }
                        return ASCLatestReview(
                            id: review.id,
                            appID: app.id,
                            appName: app.name,
                            bundleID: app.bundleID,
                            rating: rating,
                            title: normalize(attributes.title) ?? "",
                            body: normalize(attributes.body) ?? "",
                            reviewerNickname: normalize(attributes.reviewerNickname) ?? "Anonymous",
                            territory: normalize(attributes.territory),
                            createdDate: createdDate,
                            developerResponse: developerResponse
                        )
                    }

                    if let perAppCap = normalizedPerAppLimit {
                        let remaining = perAppCap - fetchedForApp
                        if remaining <= 0 {
                            break
                        }
                        if mapped.count > remaining {
                            mapped = Array(mapped.prefix(remaining))
                        }
                    }

                    fetchedForApp += mapped.count
                    merged.append(contentsOf: mapped)

                    if let totalCap = normalizedTotalLimit, merged.count >= totalCap {
                        break
                    }
                    if let perAppCap = normalizedPerAppLimit, fetchedForApp >= perAppCap {
                        break
                    }

                    if let nextLink = normalize(reviewResponse.links?.next),
                       let nextPageURL = URL(string: nextLink, relativeTo: baseURL)?.absoluteURL {
                        pageURL = nextPageURL
                    } else {
                        pageURL = nil
                    }
                }
            } catch {
                if firstFailure == nil {
                    firstFailure = error
                }
            }

            if let totalCap = normalizedTotalLimit, merged.count >= totalCap {
                break
            }
        }

        if merged.isEmpty, let firstFailure {
            throw firstFailure
        }

        merged.sort { $0.createdDate > $1.createdDate }
        if let totalCap = normalizedTotalLimit, merged.count > totalCap {
            return Array(merged.prefix(totalCap))
        }
        return merged
    }

    public func createOrUpdateCustomerReviewResponse(
        reviewID: String,
        responseBody: String
    ) async throws -> ASCLatestReviewDeveloperResponse {
        let normalizedReviewID = reviewID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedReviewID.isEmpty == false else {
            throw ASCClientError.httpStatus(-1, "Missing customer review ID.")
        }
        guard normalizedBody.isEmpty == false else {
            throw ASCClientError.httpStatus(-1, "Response body cannot be empty.")
        }

        let payload = ASCCustomerReviewResponseUpsertRequest(
            data: .init(
                attributes: .init(responseBody: normalizedBody),
                relationships: .init(
                    review: .init(
                        data: .init(id: normalizedReviewID)
                    )
                )
            )
        )
        let requestBody = try JSONEncoder().encode(payload)
        let responseData = try await request(
            path: "/v1/customerReviewResponses",
            method: .post,
            body: requestBody
        )

        if responseData.isEmpty {
            return ASCLatestReviewDeveloperResponse(
                id: nil,
                body: normalizedBody,
                lastModifiedDate: Date(),
                state: "PENDING_PUBLISH"
            )
        }

        do {
            let response = try JSONDecoder().decode(
                ASCSingleResourceResponse<ASCCustomerReviewResponseResource>.self,
                from: responseData
            )
            let attributes = response.data.attributes
            let body = normalize(attributes?.responseBody) ?? normalizedBody
            return ASCLatestReviewDeveloperResponse(
                id: response.data.id,
                body: body,
                lastModifiedDate: parseASCDate(attributes?.lastModifiedDate),
                state: normalize(attributes?.state)
            )
        } catch {
            // Keep UI responsive even if the API returns an unexpected shape.
            return ASCLatestReviewDeveloperResponse(
                id: nil,
                body: normalizedBody,
                lastModifiedDate: Date(),
                state: "PENDING_PUBLISH"
            )
        }
    }

    private func buildReviewResponseMap(
        included: [ASCIncludedResource]?
    ) -> [String: ASCLatestReviewDeveloperResponse] {
        guard let included else { return [:] }
        var mapped: [String: ASCLatestReviewDeveloperResponse] = [:]
        for resource in included {
            guard case .customerReviewResponse(let response) = resource else { continue }
            guard let attributes = response.attributes else { continue }
            guard let body = normalize(attributes.responseBody) else { continue }
            mapped[response.id] = ASCLatestReviewDeveloperResponse(
                id: response.id,
                body: body,
                lastModifiedDate: parseASCDate(attributes.lastModifiedDate),
                state: normalize(attributes.state)
            )
        }
        return mapped
    }

    private func request(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: ASCRequestMethod = .get,
        body: Data? = nil
    ) async throws -> Data {
        guard let url = makeURL(path: path, queryItems: queryItems) else {
            throw ASCClientError.invalidURL
        }
        let allowsBinaryPayload = path.hasPrefix("/v1/salesReports") || path.hasPrefix("/v1/financeReports")
        return try await request(url: url, allowsBinaryPayload: allowsBinaryPayload, method: method, body: body)
    }

    private func request(
        url: URL,
        allowsBinaryPayload: Bool = false,
        method: ASCRequestMethod = .get,
        body: Data? = nil
    ) async throws -> Data {
        await ASCRequestGate.shared.acquire()
        defer {
            Task {
                await ASCRequestGate.shared.release()
            }
        }

        var lastNetworkError: Error?
        var lastHTTPStatus: (code: Int, detail: String?)?

        for attempt in 0...maxRetryAttempts {
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.timeoutInterval = requestTimeout
            if allowsBinaryPayload {
                // Report endpoints return binary payloads (often gzip), not JSON API documents.
                request.setValue("*/*", forHTTPHeaderField: "Accept")
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Accept")
            }
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let token = try tokenProvider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                lastNetworkError = error
                if attempt < maxRetryAttempts, shouldRetryNetworkError(error) {
                    await sleepForRetry(attempt: attempt, retryAfter: nil)
                    continue
                }
                throw ASCClientError.network(error)
            }

            guard let http = response as? HTTPURLResponse else {
                throw ASCClientError.httpStatus(-1, nil)
            }

            if (200...299).contains(http.statusCode) {
                return data
            }

            let detail = extractErrorDetail(from: data)
            lastHTTPStatus = (http.statusCode, detail)

            if shouldRetryHTTPStatus(http.statusCode), attempt < maxRetryAttempts {
                await sleepForRetry(
                    attempt: attempt,
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                )
                continue
            }

            switch http.statusCode {
            case 401:
                if isTeamKeyRequiredMessage(detail) {
                    throw ASCClientError.teamKeyRequired
                }
                throw ASCClientError.unauthorized(detail)
            case 403:
                if isTeamKeyRequiredMessage(detail) {
                    throw ASCClientError.teamKeyRequired
                }
                throw ASCClientError.forbidden(detail)
            case 429:
                throw ASCClientError.rateLimited
            default:
                if isReportNotAvailableMessage(detail) {
                    throw ASCClientError.reportNotAvailableYet(detail)
                }
                throw ASCClientError.httpStatus(http.statusCode, detail)
            }
        }

        if let lastNetworkError {
            throw ASCClientError.network(lastNetworkError)
        }
        if let lastHTTPStatus {
            throw ASCClientError.httpStatus(lastHTTPStatus.code, lastHTTPStatus.detail)
        }
        throw ASCClientError.httpStatus(-1, "Unknown App Store Connect client failure.")
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if queryItems.isEmpty == false {
            components?.queryItems = queryItems
        }
        return components?.url
    }

    private func requestITunes(
        url: URL,
        userAgent: String? = nil,
        extraHeaders: [String: String] = [:],
        acceptHeader: String? = "application/json"
    ) async throws -> Data {
        var lastError: Error?
        let attempts = max(1, iTunesRetryAttempts)

        for attempt in 0..<attempts {
            if Task.isCancelled {
                throw CancellationError()
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = requestTimeout
            if let acceptHeader {
                request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
            }
            if let userAgent {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            for (header, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: header)
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ASCClientError.httpStatus(-1, nil)
                }
                guard (200...299).contains(http.statusCode) else {
                    if attempt + 1 < attempts, shouldRetryHTTPStatus(http.statusCode) {
                        let delay = retryBaseDelay * pow(2.0, Double(attempt))
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    throw ASCClientError.httpStatus(http.statusCode, nil)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt + 1 < attempts, shouldRetryNetworkError(error) {
                    let delay = retryBaseDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
        throw ASCClientError.httpStatus(-1, nil)
    }

    private func extractErrorDetail(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errors = object["errors"] as? [[String: Any]],
            let first = errors.first
        else { return nil }

        let title = first["title"] as? String
        let detail = first["detail"] as? String
        return [title, detail].compactMap { $0 }.joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTeamKeyRequiredMessage(_ message: String?) -> Bool {
        guard let text = message?.lowercased() else { return false }
        return text.contains("team key") || (text.contains("individual key") && text.contains("sales"))
    }

    private func isReportNotAvailableMessage(_ message: String?) -> Bool {
        guard let text = message?.lowercased() else { return false }
        return text.contains("report is not available yet")
            || text.contains("expected results but none were found")
            || text.contains("no results were found")
    }

    private func shouldRetryHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    private func shouldRetryNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func sleepForRetry(attempt: Int, retryAfter: String?) async {
        let backoffSeconds: TimeInterval = {
            if let retryAfter,
               let explicit = TimeInterval(retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)),
               explicit > 0 {
                return min(explicit, 10)
            }
            let exponential = retryBaseDelay * pow(2, Double(attempt))
            let jitter = Double.random(in: 0...0.25)
            return min(exponential + jitter, 10)
        }()
        let nanoseconds = UInt64(backoffSeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private func parseASCDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            return nil
        }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: value) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }
}

private enum ASCRequestMethod: String {
    case get = "GET"
    case post = "POST"
}

private struct ASCCollectionResponse<T: Decodable>: Decodable {
    let data: [T]
    let included: [ASCIncludedResource]?
    let links: ASCCollectionLinks?
}

private struct ASCCollectionLinks: Decodable {
    let next: String?
}

private struct ITunesStorefrontRating {
    let countryCode: String
    let ratingCount: Int
    let averageRating: Double
    let starCounts: [Int: Int]?
}

private struct ITunesCustomerReviewsResponse: Decodable {
    let ratingCountList: [Int]?
}

private struct ITunesLookupResponse: Decodable {
    let resultCount: Int
    let results: [ITunesLookupResult]
}

private struct ITunesLookupResult: Decodable {
    let trackId: Int?
    let averageUserRating: Double?
    let userRatingCount: Int?
}

private struct ASCSingleResourceResponse<T: Decodable>: Decodable {
    let data: T
}

private struct ASCResolvedApp {
    let id: String
    let name: String
    let bundleID: String?
}

private struct ASCAppResource: Decodable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        let name: String?
        let bundleId: String?
    }
}

private struct ASCCustomerReviewResource: Decodable {
    let id: String
    let attributes: Attributes?
    let relationships: Relationships?

    struct Attributes: Decodable {
        let rating: Int?
        let title: String?
        let body: String?
        let reviewerNickname: String?
        let territory: String?
        let createdDate: String?

        enum CodingKeys: String, CodingKey {
            case rating
            case title
            case body
            case reviewerNickname
            case territory
            case createdDate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let intValue = try container.decodeIfPresent(Int.self, forKey: .rating) {
                rating = intValue
            } else if let stringValue = try container.decodeIfPresent(String.self, forKey: .rating),
                      let intValue = Int(stringValue) {
                rating = intValue
            } else {
                rating = nil
            }
            title = try container.decodeIfPresent(String.self, forKey: .title)
            body = try container.decodeIfPresent(String.self, forKey: .body)
            reviewerNickname = try container.decodeIfPresent(String.self, forKey: .reviewerNickname)
            territory = try container.decodeIfPresent(String.self, forKey: .territory)
            createdDate = try container.decodeIfPresent(String.self, forKey: .createdDate)
        }
    }

    struct Relationships: Decodable {
        let response: ToOneRelationship?
    }
}

private struct ToOneRelationship: Decodable {
    let data: RelationshipData?
}

private struct RelationshipData: Decodable {
    let id: String
    let type: String?
}

private enum ASCIncludedResource: Decodable {
    case customerReviewResponse(ASCCustomerReviewResponseResource)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "customerReviewResponses":
            self = .customerReviewResponse(try ASCCustomerReviewResponseResource(from: decoder))
        default:
            self = .unknown
        }
    }
}

private struct ASCCustomerReviewResponseResource: Decodable {
    let id: String
    let attributes: Attributes?

    struct Attributes: Decodable {
        let responseBody: String?
        let lastModifiedDate: String?
        let state: String?
    }
}

private struct ASCCustomerReviewResponseUpsertRequest: Encodable {
    let data: DataPayload

    struct DataPayload: Encodable {
        let type = "customerReviewResponses"
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Encodable {
        let responseBody: String
    }

    struct Relationships: Encodable {
        let review: Review
    }

    struct Review: Encodable {
        let data: ReviewData
    }

    struct ReviewData: Encodable {
        let type = "customerReviews"
        let id: String
    }
}
