import XCTest
@testable import ACDCore

final class JWTSignerTests: XCTestCase {
    func testJWTSignerProducesThreeSegments() throws {
        let pem = """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgk2k5j4p9k0u9X7rM
        6fTR9+t0NenE2no0RvrRZtGJPDShRANCAAQ0BXexdFv+xo5jBqFaUG2RgxN6E466
        1ikI6jneih/7gToYtL6vhfVqlhK/SXxPxq8np5xpoE2mR7BfrpsbR9f7
        -----END PRIVATE KEY-----
        """
        let credentials = Credentials(
            issuerID: "issuer",
            keyID: "key",
            vendorNumber: "vendor",
            privateKeyPEM: pem
        )

        let token = try JWTSigner().makeToken(credentials: credentials, lifetimeSeconds: 600)
        XCTAssertEqual(token.split(separator: ".").count, 3)
    }
}
