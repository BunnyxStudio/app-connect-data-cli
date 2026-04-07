//
//  ReportParser.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import Foundation

public struct ParsedSalesRow: Sendable {
    public var lineHash: String
    public var businessDatePT: Date
    public var title: String
    public var sku: String
    public var parentIdentifier: String
    public var productTypeIdentifier: String
    public var units: Double
    public var developerProceedsPerUnit: Double
    public var currencyOfProceeds: String
    public var territory: String
    public var device: String
    public var appleIdentifier: String
    public var version: String
    public var orderType: String
    public var proceedsReason: String
    public var supportedPlatforms: String
    public var customerPrice: Double
    public var customerCurrency: String
}

public struct ParsedSubscriptionRow: Sendable {
    public var lineHash: String
    public var businessDatePT: Date
    public var appName: String
    public var appAppleID: String
    public var subscriptionName: String
    public var subscriptionAppleID: String
    public var subscriptionGroupID: String
    public var standardSubscriptionDuration: String
    public var subscriptionOfferName: String
    public var promotionalOfferID: String
    public var customerPrice: Double
    public var customerCurrency: String
    public var developerProceeds: Double
    public var proceedsCurrency: String
    public var preservedPricing: String
    public var proceedsReason: String
    public var client: String
    public var device: String
    public var state: String
    public var country: String
    public var activeStandard: Double
    public var activeIntroTrial: Double
    public var activeIntroPayUpFront: Double
    public var activeIntroPayAsYouGo: Double
    public var freeTrialPromotionalOffer: Double
    public var payUpFrontPromotionalOffer: Double
    public var payAsYouGoPromotionalOffer: Double
    public var freeTrialOfferCode: Double
    public var payUpFrontOfferCode: Double
    public var payAsYouGoOfferCode: Double
    public var marketingOptIns: Double
    public var billingRetry: Double
    public var gracePeriod: Double
    public var subscribersRaw: Double
    public var freeTrialWinBackOffers: Double
    public var payUpFrontWinBackOffers: Double
    public var payAsYouGoWinBackOffers: Double
}

public struct ParsedSubscriptionEventRow: Sendable {
    public var lineHash: String
    public var businessDatePT: Date
    public var appName: String
    public var subscriptionName: String
    public var subscriptionAppleID: String
    public var standardSubscriptionDuration: String
    public var eventName: String
    public var eventCount: Double
    public var developerProceeds: Double
    public var proceedsCurrency: String
    public var device: String
    public var country: String
}

public struct ParsedSubscriberDailyRow: Sendable {
    public var lineHash: String
    public var businessDatePT: Date
    public var appName: String
    public var subscriptionName: String
    public var subscriptionAppleID: String
    public var standardSubscriptionDuration: String
    public var subscribers: Double
    public var billingRetry: Double
    public var gracePeriod: Double
    public var developerProceeds: Double
    public var proceedsCurrency: String
    public var device: String
    public var country: String
}

public struct ParsedFinanceRow: Sendable {
    public var lineHash: String
    public var fiscalMonth: String
    public var businessDatePT: Date
    public var transactionDatePT: Date?
    public var settlementDatePT: Date?
    public var regionCode: String
    public var countryOfSale: String
    public var vendorNumber: String
    public var currency: String
    public var amount: Double
    public var units: Double
    public var salesOrReturn: String
    public var reportVariant: String
    public var productRef: String
}

public enum ReportParserError: Error {
    case malformed
}

public nonisolated struct ReportParser {
    private let minBusinessYear = 2015
    private let maxBusinessYear = 2100

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let slashDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    private let shortSlashDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        formatter.dateFormat = "M/d/yyyy"
        return formatter
    }()

    private let shortSlashYear2DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        formatter.dateFormat = "M/d/yy"
        return formatter
    }()

    private let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    public init() {}

    public func parseSales(tsv: String, fallbackDatePT: Date? = nil) throws -> [ParsedSalesRow] {
        let rows = parseRows(tsv: tsv)
        guard let header = rows.first else { return [] }
        let index = makeHeaderIndex(header)

        return rows.dropFirst().compactMap { fields in
            guard !fields.isEmpty else { return nil }
            let beginDate = preferredStringValue(
                keys: ["begin date", "start date", "event date", "date", "transaction date"],
                from: fields,
                index: index
            )
            let endDate = preferredStringValue(
                keys: ["end date", "purchase date"],
                from: fields,
                index: index
            )
            let date = resolvedBusinessDate(
                rawDate: beginDate.isEmpty ? endDate : beginDate,
                fallbackDatePT: fallbackDatePT
            )
            guard let date else { return nil }

            let title = preferredStringValue(
                keys: ["title", "subscription name", "app name", "product", "product name"],
                from: fields,
                index: index
            )
            let sku = preferredStringValue(
                keys: ["sku", "subscription apple id", "subscription id", "apple identifier"],
                from: fields,
                index: index
            )
            let parentIdentifier = preferredStringValue(
                keys: ["parent identifier", "app apple id", "parent app id"],
                from: fields,
                index: index
            )
            var productType = preferredStringValue(
                keys: ["product type identifier", "product type"],
                from: fields,
                index: index
            )
            if productType.isEmpty, index[normalizeHeader("subscription name")] != nil {
                productType = "IAY"
            }
            let units = preferredDoubleValue(
                keys: [
                    "units",
                    "quantity",
                    "subscribers",
                    "active subscriptions",
                    "paid subscriptions",
                    "active standard price subscriptions",
                    "active free trial introductory offer subscriptions",
                    "active pay up front introductory offer subscriptions",
                    "active pay as you go introductory offer subscriptions",
                    "subscriptions"
                ],
                from: fields,
                index: index
            )
            let developerProceeds = resolvedSalesProceedsPerUnit(fields: fields, index: index, units: units)
            let currency = preferredStringValue(
                keys: ["currency of proceeds", "proceeds currency", "currency"],
                from: fields,
                index: index
            ).normalizedCurrencyCode
            let territory = preferredStringValue(
                keys: ["country code", "country", "region code", "territory"],
                from: fields,
                index: index
            ).uppercased()
            let device = preferredStringValue(
                keys: ["device", "platform"],
                from: fields,
                index: index
            )
            let appleIdentifier = preferredStringValue(
                keys: ["apple identifier", "subscription apple id", "app apple id"],
                from: fields,
                index: index
            )
            let version = preferredStringValue(
                keys: ["version"],
                from: fields,
                index: index
            )
            let orderType = preferredStringValue(
                keys: ["order type"],
                from: fields,
                index: index
            )
            let proceedsReason = preferredStringValue(
                keys: ["proceeds reason"],
                from: fields,
                index: index
            )
            let supportedPlatforms = preferredStringValue(
                keys: ["supported platforms"],
                from: fields,
                index: index
            )
            let customerPrice = preferredDoubleValue(
                keys: ["customer price"],
                from: fields,
                index: index
            )
            let customerCurrency = preferredStringValue(
                keys: ["customer currency"],
                from: fields,
                index: index
            ).normalizedCurrencyCode
            let lineHash = fields.joined(separator: "\t").sha256Hex

            return ParsedSalesRow(
                lineHash: lineHash,
                businessDatePT: date,
                title: title,
                sku: sku,
                parentIdentifier: parentIdentifier,
                productTypeIdentifier: productType,
                units: units,
                developerProceedsPerUnit: developerProceeds,
                currencyOfProceeds: currency,
                territory: territory,
                device: device,
                appleIdentifier: appleIdentifier,
                version: version,
                orderType: orderType,
                proceedsReason: proceedsReason,
                supportedPlatforms: supportedPlatforms,
                customerPrice: customerPrice,
                customerCurrency: customerCurrency
            )
        }
    }

    public func parseSubscription(tsv: String, fallbackDatePT: Date? = nil) throws -> [ParsedSubscriptionRow] {
        let rows = parseRows(tsv: tsv)
        guard let header = rows.first else { return [] }
        let index = makeHeaderIndex(header)

        return rows.dropFirst().compactMap { fields in
            guard !fields.isEmpty else { return nil }
            let dateValue = preferredStringValue(
                keys: ["date", "event date", "end date", "start date", "begin date"],
                from: fields,
                index: index
            )
            let date = resolvedBusinessDate(rawDate: dateValue, fallbackDatePT: fallbackDatePT)
            guard let date else { return nil }

            let appName = preferredStringValue(keys: ["app name"], from: fields, index: index)
            let appAppleID = preferredStringValue(keys: ["app apple id"], from: fields, index: index)
            let subscriptionName = preferredStringValue(keys: ["subscription name"], from: fields, index: index)
            let subscriptionAppleID = preferredStringValue(keys: ["subscription apple id"], from: fields, index: index)
            let subscriptionGroupID = preferredStringValue(keys: ["subscription group id"], from: fields, index: index)
            let standardSubscriptionDuration = preferredStringValue(keys: ["standard subscription duration"], from: fields, index: index)
            let subscriptionOfferName = preferredStringValue(keys: ["subscription offer name"], from: fields, index: index)
            let promotionalOfferID = preferredStringValue(keys: ["promotional offer id"], from: fields, index: index)

            let customerPrice = preferredDoubleValue(keys: ["customer price"], from: fields, index: index)
            let customerCurrency = preferredStringValue(keys: ["customer currency"], from: fields, index: index).normalizedCurrencyCode
            let developerProceeds = preferredDoubleValue(keys: ["developer proceeds"], from: fields, index: index)
            let proceedsCurrency = preferredStringValue(keys: ["proceeds currency"], from: fields, index: index).normalizedCurrencyCode

            let preservedPricing = preferredStringValue(keys: ["preserved pricing"], from: fields, index: index)
            let proceedsReason = preferredStringValue(keys: ["proceeds reason"], from: fields, index: index)
            let client = preferredStringValue(keys: ["client"], from: fields, index: index)
            let device = preferredStringValue(keys: ["device"], from: fields, index: index)
            let state = preferredStringValue(keys: ["state"], from: fields, index: index)
            let country = preferredStringValue(keys: ["country"], from: fields, index: index).uppercased()

            let activeStandard = preferredDoubleValue(keys: ["active standard price subscriptions"], from: fields, index: index)
            let activeIntroTrial = preferredDoubleValue(keys: ["active free trial introductory offer subscriptions"], from: fields, index: index)
            let activeIntroPayUpFront = preferredDoubleValue(keys: ["active pay up front introductory offer subscriptions"], from: fields, index: index)
            let activeIntroPayAsYouGo = preferredDoubleValue(keys: ["active pay as you go introductory offer subscriptions"], from: fields, index: index)
            let freeTrialPromotionalOffer = preferredDoubleValue(keys: ["free trial promotional offer subscriptions"], from: fields, index: index)
            let payUpFrontPromotionalOffer = preferredDoubleValue(keys: ["pay up front promotional offer subscriptions"], from: fields, index: index)
            let payAsYouGoPromotionalOffer = preferredDoubleValue(keys: ["pay as you go promotional offer subscriptions"], from: fields, index: index)
            let freeTrialOfferCode = preferredDoubleValue(keys: ["free trial offer code subscriptions"], from: fields, index: index)
            let payUpFrontOfferCode = preferredDoubleValue(keys: ["pay up front offer code subscriptions"], from: fields, index: index)
            let payAsYouGoOfferCode = preferredDoubleValue(keys: ["pay as you go offer code subscriptions"], from: fields, index: index)
            let marketingOptIns = preferredDoubleValue(keys: ["marketing opt-ins"], from: fields, index: index)
            let billingRetry = preferredDoubleValue(keys: ["billing retry"], from: fields, index: index)
            let gracePeriod = preferredDoubleValue(keys: ["grace period"], from: fields, index: index)
            let subscribersRaw = preferredDoubleValue(keys: ["subscribers"], from: fields, index: index)
            let freeTrialWinBackOffers = preferredDoubleValue(keys: ["free trial win-back offers"], from: fields, index: index)
            let payUpFrontWinBackOffers = preferredDoubleValue(keys: ["pay up front win-back offers"], from: fields, index: index)
            let payAsYouGoWinBackOffers = preferredDoubleValue(keys: ["pay as you go win-back offers"], from: fields, index: index)

            let hasSignal =
                developerProceeds != 0
                || activeStandard != 0
                || activeIntroTrial != 0
                || activeIntroPayUpFront != 0
                || activeIntroPayAsYouGo != 0
                || subscribersRaw != 0
                || billingRetry != 0
                || gracePeriod != 0
            guard hasSignal else { return nil }

            let lineHash = fields.joined(separator: "\t").sha256Hex
            return ParsedSubscriptionRow(
                lineHash: lineHash,
                businessDatePT: date,
                appName: appName,
                appAppleID: appAppleID,
                subscriptionName: subscriptionName,
                subscriptionAppleID: subscriptionAppleID,
                subscriptionGroupID: subscriptionGroupID,
                standardSubscriptionDuration: standardSubscriptionDuration,
                subscriptionOfferName: subscriptionOfferName,
                promotionalOfferID: promotionalOfferID,
                customerPrice: customerPrice,
                customerCurrency: customerCurrency,
                developerProceeds: developerProceeds,
                proceedsCurrency: proceedsCurrency,
                preservedPricing: preservedPricing,
                proceedsReason: proceedsReason,
                client: client,
                device: device,
                state: state,
                country: country,
                activeStandard: activeStandard,
                activeIntroTrial: activeIntroTrial,
                activeIntroPayUpFront: activeIntroPayUpFront,
                activeIntroPayAsYouGo: activeIntroPayAsYouGo,
                freeTrialPromotionalOffer: freeTrialPromotionalOffer,
                payUpFrontPromotionalOffer: payUpFrontPromotionalOffer,
                payAsYouGoPromotionalOffer: payAsYouGoPromotionalOffer,
                freeTrialOfferCode: freeTrialOfferCode,
                payUpFrontOfferCode: payUpFrontOfferCode,
                payAsYouGoOfferCode: payAsYouGoOfferCode,
                marketingOptIns: marketingOptIns,
                billingRetry: billingRetry,
                gracePeriod: gracePeriod,
                subscribersRaw: subscribersRaw,
                freeTrialWinBackOffers: freeTrialWinBackOffers,
                payUpFrontWinBackOffers: payUpFrontWinBackOffers,
                payAsYouGoWinBackOffers: payAsYouGoWinBackOffers
            )
        }
    }

    public func parseSubscriptionEvent(tsv: String, fallbackDatePT: Date? = nil) throws -> [ParsedSubscriptionEventRow] {
        let rows = parseRows(tsv: tsv)
        guard let header = rows.first else { return [] }
        let index = makeHeaderIndex(header)

        return rows.dropFirst().compactMap { fields in
            guard !fields.isEmpty else { return nil }
            let dateValue = preferredStringValue(
                keys: ["date", "event date", "end date", "start date", "begin date"],
                from: fields,
                index: index
            )
            let date = resolvedBusinessDate(rawDate: dateValue, fallbackDatePT: fallbackDatePT)
            guard let date else { return nil }

            let appName = preferredStringValue(
                keys: ["app name", "title"],
                from: fields,
                index: index
            )
            let subscriptionName = preferredStringValue(
                keys: ["subscription name", "product", "product name"],
                from: fields,
                index: index
            )
            let subscriptionAppleID = preferredStringValue(
                keys: ["subscription apple id", "subscription id", "apple identifier"],
                from: fields,
                index: index
            )
            let standardSubscriptionDuration = preferredStringValue(
                keys: ["standard subscription duration"],
                from: fields,
                index: index
            )
            let eventName = preferredStringValue(
                keys: ["event", "event type", "subscription event", "event name"],
                from: fields,
                index: index
            )
            let eventCount = preferredDoubleValue(
                keys: ["events", "event count", "quantity", "units", "subscribers"],
                from: fields,
                index: index
            )
            let developerProceeds = preferredDoubleValue(
                keys: ["developer proceeds", "proceeds", "partner share"],
                from: fields,
                index: index
            )
            let proceedsCurrency = preferredStringValue(
                keys: ["proceeds currency", "currency of proceeds", "currency"],
                from: fields,
                index: index
            ).normalizedCurrencyCode
            let device = preferredStringValue(
                keys: ["device", "platform", "client"],
                from: fields,
                index: index
            )
            let country = preferredStringValue(
                keys: ["country", "country code", "territory", "region code"],
                from: fields,
                index: index
            ).uppercased()

            guard !eventName.isEmpty || eventCount != 0 || developerProceeds != 0 else {
                return nil
            }

            return ParsedSubscriptionEventRow(
                lineHash: fields.joined(separator: "\t").sha256Hex,
                businessDatePT: date,
                appName: appName,
                subscriptionName: subscriptionName,
                subscriptionAppleID: subscriptionAppleID,
                standardSubscriptionDuration: standardSubscriptionDuration,
                eventName: eventName,
                eventCount: eventCount,
                developerProceeds: developerProceeds,
                proceedsCurrency: proceedsCurrency,
                device: device,
                country: country
            )
        }
    }

    public func parseSubscriberDaily(tsv: String, fallbackDatePT: Date? = nil) throws -> [ParsedSubscriberDailyRow] {
        let rows = parseRows(tsv: tsv)
        guard let header = rows.first else { return [] }
        let index = makeHeaderIndex(header)

        return rows.dropFirst().compactMap { fields in
            guard !fields.isEmpty else { return nil }
            let dateValue = preferredStringValue(
                keys: ["date", "event date", "end date", "start date", "begin date"],
                from: fields,
                index: index
            )
            let date = resolvedBusinessDate(rawDate: dateValue, fallbackDatePT: fallbackDatePT)
            guard let date else { return nil }

            let appName = preferredStringValue(
                keys: ["app name", "title"],
                from: fields,
                index: index
            )
            let subscriptionName = preferredStringValue(
                keys: ["subscription name", "product", "product name"],
                from: fields,
                index: index
            )
            let subscriptionAppleID = preferredStringValue(
                keys: ["subscription apple id", "subscription id", "apple identifier"],
                from: fields,
                index: index
            )
            let standardSubscriptionDuration = preferredStringValue(
                keys: ["standard subscription duration"],
                from: fields,
                index: index
            )
            let subscribers = preferredDoubleValue(
                keys: ["subscribers", "active subscribers", "active subscriptions", "units"],
                from: fields,
                index: index
            )
            let billingRetry = preferredDoubleValue(
                keys: ["billing retry"],
                from: fields,
                index: index
            )
            let gracePeriod = preferredDoubleValue(
                keys: ["grace period"],
                from: fields,
                index: index
            )
            let developerProceeds = preferredDoubleValue(
                keys: ["developer proceeds", "proceeds", "partner share"],
                from: fields,
                index: index
            )
            let proceedsCurrency = preferredStringValue(
                keys: ["proceeds currency", "currency of proceeds", "currency"],
                from: fields,
                index: index
            ).normalizedCurrencyCode
            let device = preferredStringValue(
                keys: ["device", "platform", "client"],
                from: fields,
                index: index
            )
            let country = preferredStringValue(
                keys: ["country", "country code", "territory", "region code"],
                from: fields,
                index: index
            ).uppercased()

            guard subscribers != 0 || billingRetry != 0 || gracePeriod != 0 || developerProceeds != 0 else {
                return nil
            }

            return ParsedSubscriberDailyRow(
                lineHash: fields.joined(separator: "\t").sha256Hex,
                businessDatePT: date,
                appName: appName,
                subscriptionName: subscriptionName,
                subscriptionAppleID: subscriptionAppleID,
                standardSubscriptionDuration: standardSubscriptionDuration,
                subscribers: subscribers,
                billingRetry: billingRetry,
                gracePeriod: gracePeriod,
                developerProceeds: developerProceeds,
                proceedsCurrency: proceedsCurrency,
                device: device,
                country: country
            )
        }
    }

    public func parseFinance(
        tsv: String,
        fiscalMonth: String,
        regionCode: String,
        vendorNumber: String,
        reportVariant: String
    ) throws -> [ParsedFinanceRow] {
        let rows = parseRows(tsv: tsv)
        guard let headerOffset = findFinanceHeaderOffset(in: rows) else { return [] }
        let header = rows[headerOffset]
        let index = makeHeaderIndex(header)

        return rows.dropFirst(headerOffset + 1).compactMap { fields in
            guard !fields.isEmpty else { return nil }
            if shouldSkipFinanceRow(fields, index: index) {
                return nil
            }
            let currency = preferredStringValue(
                keys: [
                    "partner share currency",
                    "partner share currency code",
                    "currency of proceeds",
                    "proceeds currency",
                    "customer currency",
                    "reporting currency",
                    "currency"
                ],
                from: fields,
                index: index
            ).normalizedCurrencyCode
            let units = preferredDoubleValue(
                keys: ["units", "quantity"],
                from: fields,
                index: index
            )
            let salesOrReturn = preferredStringValue(
                keys: ["sales or return", "sale or return"],
                from: fields,
                index: index
            )
            let amount = applySalesDirection(
                resolvedFinanceAmount(fields: fields, index: index, units: units),
                salesOrReturn: salesOrReturn
            )
            let signedUnits = applySalesDirection(units, salesOrReturn: salesOrReturn)
            let transactionDate = preferredStringValue(
                keys: ["transaction date", "start date", "begin date", "end date"],
                from: fields,
                index: index
            )
            let settlementDate = preferredStringValue(
                keys: ["settlement date", "end date"],
                from: fields,
                index: index
            )
            let parsedTransactionDate = parseDate(transactionDate)
            let parsedSettlementDate = parseDate(settlementDate)
            let businessDate = parsedTransactionDate
                ?? DateFormatter.fiscalMonthFormatter.date(from: fiscalMonth)
                ?? Date()
            let countryOfSale = preferredStringValue(
                keys: ["country of sale", "country code", "country"],
                from: fields,
                index: index
            ).uppercased()
            let productRef = preferredStringValue(
                keys: ["sku", "title", "product", "description", "apple identifier"],
                from: fields,
                index: index
            )
            if amount == 0, signedUnits == 0, productRef.isEmpty {
                return nil
            }
            let lineHash = fields.joined(separator: "\t").sha256Hex

            return ParsedFinanceRow(
                lineHash: lineHash,
                fiscalMonth: fiscalMonth,
                businessDatePT: businessDate,
                transactionDatePT: parsedTransactionDate,
                settlementDatePT: parsedSettlementDate,
                regionCode: regionCode,
                countryOfSale: countryOfSale,
                vendorNumber: vendorNumber,
                currency: currency,
                amount: amount,
                units: signedUnits,
                salesOrReturn: salesOrReturn,
                reportVariant: reportVariant,
                productRef: productRef
            )
        }
    }

    private func parseRows(tsv: String) -> [[String]] {
        tsv.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.hasPrefix("#") }
            .map { $0.components(separatedBy: "\t") }
    }

    private func findFinanceHeaderOffset(in rows: [[String]]) -> Int? {
        for (offset, row) in rows.enumerated() {
            let normalized = row.map(normalizeHeader)
            let hasPartnerShare = normalized.contains("partner share")
            let hasExtendedShare = normalized.contains("extended partner share")
            let hasQuantity = normalized.contains("quantity") || normalized.contains("units")
            let hasCurrency = normalized.contains("partner share currency") || normalized.contains("partner share currency code")
            if hasPartnerShare, hasExtendedShare, hasQuantity, hasCurrency {
                return offset
            }
        }
        return nil
    }

    private func makeHeaderIndex(_ header: [String]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (offset, name) in header.enumerated() {
            index[normalizeHeader(name)] = offset
        }
        return index
    }

    private func normalizeHeader(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = dateFormatter.date(from: trimmed) {
            return date
        }
        if let date = compactDateFormatter.date(from: trimmed) {
            return date
        }
        if let date = slashDateFormatter.date(from: trimmed) {
            return date
        }
        if let date = shortSlashDateFormatter.date(from: trimmed) {
            return date
        }
        if let date = shortSlashYear2DateFormatter.date(from: trimmed) {
            return date
        }
        if trimmed.count == 7 {
            return DateFormatter.fiscalMonthFormatter.date(from: trimmed)
        }
        return nil
    }

    private func resolvedBusinessDate(rawDate: String, fallbackDatePT: Date?) -> Date? {
        guard let parsed = parseDate(rawDate) else {
            return fallbackDatePT
        }
        let year = Calendar(identifier: .gregorian).component(.year, from: parsed)
        guard year >= minBusinessYear, year <= maxBusinessYear else {
            return fallbackDatePT
        }
        return parsed
    }

    private func stringValue(_ key: String, from fields: [String], index: [String: Int]) -> String {
        guard let offset = index[normalizeHeader(key)], offset < fields.count else { return "" }
        return fields[offset].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldSkipFinanceRow(_ fields: [String], index: [String: Int]) -> Bool {
        let firstCell = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if firstCell == "total_rows" || firstCell == "country of sale" {
            return true
        }

        let saleOrReturn = preferredStringValue(
            keys: ["sales or return", "sale or return"],
            from: fields,
            index: index
        ).uppercased()
        let hasSalesMarker = saleOrReturn == "S" || saleOrReturn == "R"

        let qty = preferredDoubleValue(keys: ["quantity", "units"], from: fields, index: index)
        let ext = preferredDoubleValue(keys: ["extended partner share"], from: fields, index: index)
        let partner = preferredDoubleValue(keys: ["partner share"], from: fields, index: index)

        if !hasSalesMarker, qty == 0, ext == 0, partner == 0 {
            return true
        }
        return false
    }

    private func preferredStringValue(keys: [String], from fields: [String], index: [String: Int]) -> String {
        for key in keys {
            let value = stringValue(key, from: fields, index: index)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func doubleValue(_ key: String, from fields: [String], index: [String: Int]) -> Double {
        let raw = stringValue(key, from: fields, index: index)
        return parseDouble(raw)
    }

    private func parseDouble(_ raw: String) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        let isParenthesizedNegative = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        var sanitized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            return 0
        }

        if let value = Double(sanitized) {
            return isParenthesizedNegative ? -abs(value) : value
        }

        // Keep only numeric/sign/decimal characters as a final fallback.
        sanitized = sanitized.replacingOccurrences(of: #"[^0-9\.\-]+"#, with: "", options: .regularExpression)
        guard let fallback = Double(sanitized) else {
            return 0
        }
        return isParenthesizedNegative ? -abs(fallback) : fallback
    }

    private func preferredDoubleValue(keys: [String], from fields: [String], index: [String: Int]) -> Double {
        for key in keys {
            let value = doubleValue(key, from: fields, index: index)
            if value != 0 {
                return value
            }
        }
        return 0
    }

    private func resolvedSalesProceedsPerUnit(fields: [String], index: [String: Int], units: Double) -> Double {
        let perUnit = preferredDoubleValue(
            keys: ["developer proceeds", "proceeds", "proceeds (developer proceeds)", "partner share"],
            from: fields,
            index: index
        )
        let extended = preferredDoubleValue(
            keys: ["extended partner share"],
            from: fields,
            index: index
        )
        if perUnit != 0 {
            return perUnit
        }
        if extended != 0, units > 0 {
            return extended / units
        }
        return 0
    }

    private func resolvedFinanceAmount(fields: [String], index: [String: Int], units: Double) -> Double {
        let extended = preferredDoubleValue(
            keys: ["extended partner share"],
            from: fields,
            index: index
        )
        if extended != 0 {
            return extended
        }

        let total = preferredDoubleValue(
            keys: ["total owed", "proceeds", "developer proceeds", "amount"],
            from: fields,
            index: index
        )
        if total != 0 {
            return total
        }

        let partnerShare = preferredDoubleValue(
            keys: ["partner share"],
            from: fields,
            index: index
        )
        if partnerShare != 0 {
            return units > 0 ? partnerShare * units : partnerShare
        }
        return 0
    }

    private func applySalesDirection(_ value: Double, salesOrReturn: String) -> Double {
        let marker = salesOrReturn.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !marker.isEmpty else { return value }
        switch marker {
        case "R":
            return -abs(value)
        case "S":
            return abs(value)
        default:
            return value
        }
    }
}
