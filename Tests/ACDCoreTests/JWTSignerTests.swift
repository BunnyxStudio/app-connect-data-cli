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
