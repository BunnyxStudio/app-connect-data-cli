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

public enum SalesReportFamily: String, Codable, CaseIterable, Sendable {
    case summarySales = "summary-sales"
    case subscription
    case subscriptionEvent = "subscription-event"
    case subscriber
    case preOrder = "pre-order"
    case subscriptionOfferRedemption = "subscription-offer-redemption"
}

public enum ASCAnalyticsAccessType: String, Codable, CaseIterable, Sendable {
    case ongoing = "ONGOING"
    case oneTimeSnapshot = "ONE_TIME_SNAPSHOT"
}

public enum ASCAnalyticsCategory: String, Codable, CaseIterable, Sendable {
    case appUsage = "APP_USAGE"
    case appStoreEngagement = "APP_STORE_ENGAGEMENT"
    case commerce = "COMMERCE"
    case frameworkUsage = "FRAMEWORK_USAGE"
    case performance = "PERFORMANCE"
}

public enum ASCAnalyticsGranularity: String, Codable, CaseIterable, Sendable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
}

public struct ASCAppSummary: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var bundleID: String?

    public init(id: String, name: String, bundleID: String?) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
    }
}

public struct ASCAnalyticsReportRequest: Codable, Equatable, Sendable {
    public var id: String
    public var accessType: ASCAnalyticsAccessType?
    public var stoppedDueToInactivity: Bool

    public init(id: String, accessType: ASCAnalyticsAccessType?, stoppedDueToInactivity: Bool) {
        self.id = id
        self.accessType = accessType
        self.stoppedDueToInactivity = stoppedDueToInactivity
    }
}

public struct ASCAnalyticsReport: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var category: ASCAnalyticsCategory?

    public init(id: String, name: String, category: ASCAnalyticsCategory?) {
        self.id = id
        self.name = name
        self.category = category
    }
}

public struct ASCAnalyticsReportInstance: Codable, Equatable, Sendable {
    public var id: String
    public var granularity: ASCAnalyticsGranularity?
    public var processingDate: String?

    public init(id: String, granularity: ASCAnalyticsGranularity?, processingDate: String?) {
        self.id = id
        self.granularity = granularity
        self.processingDate = processingDate
    }
}

public struct ASCAnalyticsReportSegment: Codable, Equatable, Sendable {
    public var id: String
    public var url: URL?
    public var checksum: String?
    public var sizeInBytes: Int?

    public init(id: String, url: URL?, checksum: String?, sizeInBytes: Int?) {
        self.id = id
        self.url = url
        self.checksum = checksum
        self.sizeInBytes = sizeInBytes
    }
}
