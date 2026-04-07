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
import ACDAnalytics

enum RuntimeError: LocalizedError {
    case missingHomeDirectory

    var errorDescription: String? {
        switch self {
        case .missingHomeDirectory:
            return "Unable to resolve home directory."
        }
    }
}

enum CredentialsMode {
    case disabled
    case optional
    case required
}

struct RuntimePaths {
    var workingDirectory: URL
    var localBase: URL
    var userBase: URL
    var activeBase: URL
    var cacheRoot: URL
}

struct CredentialsOverrides {
    var issuerID: String?
    var keyID: String?
    var vendorNumber: String?
    var p8Path: String?
}

struct RuntimeContext {
    var config: ACDConfig
    var credentials: Credentials?
    var paths: RuntimePaths
    var cacheStore: CacheStore
    var client: ASCClient?
    var downloader: ReportDownloader?
    var syncService: SyncService?
    var analytics: AnalyticsEngine
}

enum RuntimeFactory {
    static func make(
        overrides: CredentialsOverrides = CredentialsOverrides(),
        credentialsMode: CredentialsMode
    ) throws -> RuntimeContext {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let localBase = cwd.appendingPathComponent(".app-connect-data-cli", isDirectory: true)
        guard let homeDirectory = fileManager.homeDirectoryForCurrentUser as URL? else {
            throw RuntimeError.missingHomeDirectory
        }
        let userBase = homeDirectory.appendingPathComponent(".app-connect-data-cli", isDirectory: true)
        let activeBase: URL
        if fileManager.fileExists(atPath: localBase.appendingPathComponent("cache").path)
            || fileManager.fileExists(atPath: localBase.appendingPathComponent("config.json").path)
            || fileManager.fileExists(atPath: localBase.path) {
            activeBase = localBase
        } else {
            activeBase = userBase
        }
        let cacheRoot = activeBase.appendingPathComponent("cache", isDirectory: true)
        let paths = RuntimePaths(
            workingDirectory: cwd,
            localBase: localBase,
            userBase: userBase,
            activeBase: activeBase,
            cacheRoot: cacheRoot
        )
        try LocalFileSecurity.ensurePrivateDirectory(activeBase, fileManager: fileManager)
        let config = try resolveConfig(paths: paths, overrides: overrides)
        let cacheStore = CacheStore(rootDirectory: cacheRoot)
        try cacheStore.prepare()

        if credentialsMode == .disabled {
            return RuntimeContext(
                config: config,
                credentials: nil,
                paths: paths,
                cacheStore: cacheStore,
                client: nil,
                downloader: nil,
                syncService: nil,
                analytics: AnalyticsEngine(
                    cacheStore: cacheStore,
                    reportingCurrency: config.reportingCurrency ?? "USD"
                )
            )
        }

        let hasCredentialHints = [config.issuerID, config.keyID, config.vendorNumber, config.p8Path]
            .contains { value in
                guard let value else { return false }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        if credentialsMode == .optional, hasCredentialHints == false {
            return RuntimeContext(
                config: config,
                credentials: nil,
                paths: paths,
                cacheStore: cacheStore,
                client: nil,
                downloader: nil,
                syncService: nil,
                analytics: AnalyticsEngine(
                    cacheStore: cacheStore,
                    reportingCurrency: config.reportingCurrency ?? "USD"
                )
            )
        }

        let privateKeyPEM = try resolvedPrivateKeyPEM(config: config)
        let credentials = try CredentialsResolver.validate(
            issuerID: config.issuerID,
            keyID: config.keyID,
            vendorNumber: config.vendorNumber,
            privateKeyPEM: privateKeyPEM
        )
        let signer = JWTSigner()
        let client = ASCClient(
            session: .shared,
            tokenProvider: {
                try signer.makeToken(credentials: credentials, lifetimeSeconds: 1200)
            }
        )
        let downloader = ReportDownloader(
            fileManager: fileManager,
            client: client,
            credentialsProvider: { credentials },
            reportsRootDirectoryURL: cacheStore.reportsDirectory
        )
        let syncService = SyncService(cacheStore: cacheStore, downloader: downloader, client: client)
        let analytics = AnalyticsEngine(
            cacheStore: cacheStore,
            syncService: syncService,
            client: client,
            downloader: downloader
            ,
            reportingCurrency: config.reportingCurrency ?? "USD"
        )
        return RuntimeContext(
            config: config,
            credentials: credentials,
            paths: paths,
            cacheStore: cacheStore,
            client: client,
            downloader: downloader,
            syncService: syncService,
            analytics: analytics
        )
    }

    private static func resolveConfig(paths: RuntimePaths, overrides: CredentialsOverrides) throws -> ACDConfig {
        let userConfig = try loadConfig(at: paths.userBase.appendingPathComponent("config.json"))
        let localConfig = try loadConfig(at: paths.localBase.appendingPathComponent("config.json"))
        let env = ProcessInfo.processInfo.environment

        return ACDConfig(
            issuerID: firstNonEmpty(overrides.issuerID, env["ASC_ISSUER_ID"], localConfig?.issuerID, userConfig?.issuerID),
            keyID: firstNonEmpty(overrides.keyID, env["ASC_KEY_ID"], localConfig?.keyID, userConfig?.keyID),
            vendorNumber: firstNonEmpty(overrides.vendorNumber, env["ASC_VENDOR_NUMBER"], localConfig?.vendorNumber, userConfig?.vendorNumber),
            p8Path: firstNonEmpty(overrides.p8Path, env["ASC_P8_PATH"], localConfig?.p8Path, userConfig?.p8Path),
            reportingCurrency: firstNonEmpty(
                env["ADC_REPORTING_CURRENCY"],
                localConfig?.reportingCurrency,
                userConfig?.reportingCurrency
            )?.normalizedCurrencyCode,
            displayTimeZone: normalizedTimeZoneIdentifier(
                firstNonEmpty(
                    env["ADC_DISPLAY_TIMEZONE"],
                    localConfig?.displayTimeZone,
                    userConfig?.displayTimeZone
                )
            )
        )
    }

    static func loadConfig(at url: URL) throws -> ACDConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try LocalFileSecurity.validateOwnerOnlyFile(url)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ACDConfig.self, from: data)
    }

    static func saveConfig(_ config: ACDConfig, at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try LocalFileSecurity.writePrivateData(data, to: url)
    }

    private static func resolvedPrivateKeyPEM(config: ACDConfig) throws -> String {
        guard let p8Path = config.p8Path else { throw SetupValidationError.missingP8 }
        let url = URL(fileURLWithPath: p8Path)
        try LocalFileSecurity.validateOwnerOnlyFile(url)
        return try P8Importer().loadPrivateKeyPEM(from: url)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private static func normalizedTimeZoneIdentifier(_ value: String?) -> String? {
        guard let trimmed = firstNonEmpty(value) else { return nil }
        guard TimeZone(identifier: trimmed) != nil else { return nil }
        return trimmed
    }
}
