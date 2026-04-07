//
//  JWTSigner.swift
//  ACD
//
//  Created by Codex on 2026/2/20.
//

import CryptoKit
import Foundation

public enum JWTSignerError: Error {
    case invalidPrivateKey
    case signingFailed
}

public struct JWTSigner: JWTSignerProtocol {
    public init() {}

    public func makeToken(credentials: Credentials, lifetimeSeconds: TimeInterval = 1200) throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let ttl = max(1, min(Int(lifetimeSeconds), 1200))
        let exp = now + ttl

        let header: [String: String] = [
            "alg": "ES256",
            "kid": credentials.keyID,
            "typ": "JWT"
        ]

        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": now,
            "exp": exp,
            "aud": "appstoreconnect-v1"
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let headerPart = base64URLEncoded(headerData)
        let payloadPart = base64URLEncoded(payloadData)
        let signingInput = "\(headerPart).\(payloadPart)"

        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        } catch {
            throw JWTSignerError.invalidPrivateKey
        }

        guard let signingData = signingInput.data(using: .utf8) else {
            throw JWTSignerError.signingFailed
        }

        let signature: P256.Signing.ECDSASignature
        do {
            signature = try privateKey.signature(for: signingData)
        } catch {
            throw JWTSignerError.signingFailed
        }

        let signaturePart = base64URLEncoded(signature.rawRepresentation)
        return "\(signingInput).\(signaturePart)"
    }

    private func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
