import Foundation
import ACDCore
import ACDAnalytics

enum RuntimeError: LocalizedError {
    case missingHomeDirectory
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .missingHomeDirectory:
            return "Unable to resolve home directory."
        case .invalidDate(let value):
            return "Invalid PT date: \(value)"
        }
    }
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
        requireCredentials: Bool
    ) throws -> RuntimeContext {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let localBase = cwd.appendingPathComponent(".acd", isDirectory: true)
        guard let homeDirectory = fileManager.homeDirectoryForCurrentUser as URL? else {
            throw RuntimeError.missingHomeDirectory
        }
        let userBase = homeDirectory.appendingPathComponent(".acd", isDirectory: true)
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
        let config = try resolveConfig(paths: paths, overrides: overrides)
        let cacheStore = CacheStore(rootDirectory: cacheRoot)
        try cacheStore.prepare()
        let analytics = AnalyticsEngine(
            cacheStore: cacheStore,
            fxService: FXRateService(cacheURL: cacheStore.fxCacheURL)
        )
        if requireCredentials == false {
            return RuntimeContext(
                config: config,
                credentials: nil,
                paths: paths,
                cacheStore: cacheStore,
                client: nil,
                downloader: nil,
                syncService: nil,
                analytics: analytics
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
            p8Path: firstNonEmpty(overrides.p8Path, env["ASC_P8_PATH"], localConfig?.p8Path, userConfig?.p8Path)
        )
    }

    private static func loadConfig(at url: URL) throws -> ACDConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ACDConfig.self, from: data)
    }

    private static func resolvedPrivateKeyPEM(config: ACDConfig) throws -> String {
        guard let p8Path = config.p8Path else { throw SetupValidationError.missingP8 }
        return try P8Importer().loadPrivateKeyPEM(from: URL(fileURLWithPath: p8Path))
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { $0 }.first { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }
}

func parsePTDateInput(_ value: String) throws -> Date {
    if let date = PTDate(value).date {
        return date
    }
    throw RuntimeError.invalidDate(value)
}

func recentPTDates(days: Int, endingAt reference: Date = Date()) -> [Date] {
    let clamped = max(1, days)
    let calendar = Calendar.pacific
    let today = calendar.startOfDay(for: reference)
    return (0..<clamped).compactMap { offset in
        calendar.date(byAdding: .day, value: -offset - 1, to: today)
    }.sorted()
}

func recentFiscalMonths(count: Int, reference: Date = Date()) -> [String] {
    let clamped = max(1, count)
    let calendar = Calendar.pacific
    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)) ?? reference
    return (0..<clamped).compactMap { offset in
        calendar.date(byAdding: .month, value: -offset, to: monthStart)?.fiscalMonthString
    }.sorted()
}
