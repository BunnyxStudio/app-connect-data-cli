import Foundation

public struct ACDConfig: Codable, Equatable, Sendable {
    public var issuerID: String?
    public var keyID: String?
    public var vendorNumber: String?
    public var p8Path: String?

    public init(
        issuerID: String? = nil,
        keyID: String? = nil,
        vendorNumber: String? = nil,
        p8Path: String? = nil
    ) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.vendorNumber = vendorNumber
        self.p8Path = p8Path
    }
}

public enum CredentialsResolver {
    public static func validate(
        issuerID: String?,
        keyID: String?,
        vendorNumber: String?,
        privateKeyPEM: String?
    ) throws -> Credentials {
        guard let issuerID, issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SetupValidationError.missingIssuer
        }
        guard let keyID, keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SetupValidationError.missingKeyID
        }
        guard let vendorNumber, vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SetupValidationError.missingVendor
        }
        guard let privateKeyPEM, privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw SetupValidationError.missingP8
        }
        return Credentials(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            vendorNumber: vendorNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM
        )
    }
}
