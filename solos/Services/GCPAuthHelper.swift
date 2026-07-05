import Foundation

/// Shared GCP OAuth2 helper — mints a JWT from the bundled service-account JSON and
/// exchanges it for a short-lived Bearer token (scope: cloud-platform).
/// Used by Gemini (Vertex AI), Google STT, and Google TTS.
actor GCPAuthHelper {
    static let shared = GCPAuthHelper()

    private struct CachedToken {
        let accessToken: String
        let expiry: Date
        var isValid: Bool { Date() < expiry.addingTimeInterval(-60) }
    }

    private var cachedToken: CachedToken?

    private static let gcpScope = "https://www.googleapis.com/auth/cloud-platform"

    // MARK: - Service-account JSON path

    static var serviceAccountURL: URL? {
        // 1. Bundled resource
        if let url = Bundle.main.url(forResource: "gemini-service-account", withExtension: "json") {
            return url
        }
        // 2. Dev convenience path relative to this source file
        let devPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()       // Services/
            .deletingLastPathComponent()       // solos/
            .appendingPathComponent("Config/gemini-service-account.json")
        return FileManager.default.fileExists(atPath: devPath.path) ? devPath : nil
    }

    static var isAvailable: Bool { serviceAccountURL != nil }

    // MARK: - Token

    /// Returns a valid Bearer token, re-minting if the cached one is expired.
    func bearerToken() async throws -> String {
        if let cached = cachedToken, cached.isValid {
            return cached.accessToken
        }
        let token = try await mintToken()
        cachedToken = token
        return token.accessToken
    }

    // MARK: - JWT minting + token exchange

    private func mintToken() async throws -> CachedToken {
        guard let saURL = GCPAuthHelper.serviceAccountURL,
              let saData = try? Data(contentsOf: saURL) else {
            throw GCPAuthError.cannotReadServiceAccount
        }

        let sa: ServiceAccountJSON
        do {
            sa = try ServiceAccountJSON.from(data: saData)
        } catch {
            throw GCPAuthError.invalidServiceAccount("Decode failed: \(error)")
        }

        guard sa.type == "service_account" else {
            throw GCPAuthError.invalidServiceAccount("Expected type=service_account, got '\(sa.type)'")
        }

        SoloChefLog.info("gcp-auth: minting JWT — email=\(sa.client_email) project=\(sa.project_id)")

        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 3600

        let header  = base64url(try jsonData(["alg": "RS256", "typ": "JWT", "kid": sa.private_key_id]))
        let payload = base64url(try jsonData([
            "iss":   sa.client_email,
            "sub":   sa.client_email,
            "aud":   sa.token_uri,
            "iat":   now,
            "exp":   exp,
            "scope": GCPAuthHelper.gcpScope
        ]))
        let signingInput = "\(header).\(payload)"
        guard let signingData = signingInput.data(using: .ascii) else {
            throw GCPAuthError.invalidServiceAccount("Cannot encode JWT signing input as ASCII")
        }

        let signature = try rsaSign(data: signingData, pemKey: sa.private_key)
        let jwt = "\(signingInput).\(base64url(signature))"

        // Exchange JWT for access token
        var tokenReq = URLRequest(url: URL(string: sa.token_uri)!)
        tokenReq.httpMethod = "POST"
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenReq.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
            .data(using: .ascii)

        let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenReq)
        let rawToken = String(data: tokenData, encoding: .utf8) ?? ""

        guard let http = tokenResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GCPAuthError.tokenExchangeFailed(
                "HTTP \((tokenResp as? HTTPURLResponse)?.statusCode ?? 0): \(rawToken.prefix(200))"
            )
        }

        guard let json = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw GCPAuthError.tokenExchangeFailed("Cannot parse access_token from: \(rawToken.prefix(200))")
        }

        let expiresIn = json["expires_in"] as? Int ?? 3600
        SoloChefLog.info("gcp-auth: token acquired — expires in \(expiresIn)s")
        return CachedToken(
            accessToken: accessToken,
            expiry: Date().addingTimeInterval(Double(expiresIn))
        )
    }

    // MARK: - Crypto helpers

    private func jsonData(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func rsaSign(data: Data, pemKey: String) throws -> Data {
        let stripped = pemKey
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let pkcs8Der = Data(base64Encoded: stripped) else {
            throw GCPAuthError.invalidServiceAccount("Cannot base64-decode private key DER")
        }

        let derData = try pkcs1DER(from: pkcs8Der)

        let attrs: [CFString: Any] = [
            kSecAttrKeyType:       kSecAttrKeyTypeRSA,
            kSecAttrKeyClass:      kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048
        ]
        var cfError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derData as CFData, attrs as CFDictionary, &cfError) else {
            let msg = cfError?.takeRetainedValue().localizedDescription ?? "unknown"
            throw GCPAuthError.invalidServiceAccount("Cannot import RSA key: \(msg)")
        }

        guard SecKeyIsAlgorithmSupported(secKey, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw GCPAuthError.invalidServiceAccount("RSA-SHA256 not supported on this key")
        }

        guard let sig = SecKeyCreateSignature(
            secKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &cfError
        ) as Data? else {
            let msg = cfError?.takeRetainedValue().localizedDescription ?? "unknown"
            throw GCPAuthError.invalidServiceAccount("RSA signing failed: \(msg)")
        }

        return sig
    }

    /// Extracts the inner PKCS#1 RSA private key from a PKCS#8 DER-encoded key.
    private func pkcs1DER(from pkcs8: Data) throws -> Data {
        var idx = pkcs8.startIndex

        func readByte() throws -> UInt8 {
            guard idx < pkcs8.endIndex else {
                throw GCPAuthError.invalidServiceAccount("PKCS#8 DER truncated")
            }
            defer { idx = pkcs8.index(after: idx) }
            return pkcs8[idx]
        }

        func readLength() throws -> Int {
            let first = try readByte()
            if first & 0x80 == 0 { return Int(first) }
            let numBytes = Int(first & 0x7F)
            guard numBytes > 0, numBytes <= 4 else {
                throw GCPAuthError.invalidServiceAccount("PKCS#8 DER: unsupported length encoding")
            }
            var len = 0
            for _ in 0..<numBytes { len = (len << 8) | Int(try readByte()) }
            return len
        }

        guard try readByte() == 0x30 else {
            throw GCPAuthError.invalidServiceAccount("PKCS#8 DER: expected outer SEQUENCE tag")
        }
        _ = try readLength()
        guard try readByte() == 0x02 else {
            throw GCPAuthError.invalidServiceAccount("PKCS#8 DER: expected version INTEGER tag")
        }
        let versionLen = try readLength()
        idx = pkcs8.index(idx, offsetBy: versionLen)
        guard try readByte() == 0x30 else {
            throw GCPAuthError.invalidServiceAccount("PKCS#8 DER: expected AlgorithmIdentifier SEQUENCE tag")
        }
        let algLen = try readLength()
        idx = pkcs8.index(idx, offsetBy: algLen)
        guard try readByte() == 0x04 else {
            throw GCPAuthError.invalidServiceAccount("PKCS#8 DER: expected OCTET STRING tag")
        }
        let octetLen = try readLength()
        let pkcs1Start = idx
        let pkcs1End   = pkcs8.index(pkcs1Start, offsetBy: octetLen)
        guard pkcs1End <= pkcs8.endIndex else {
            throw GCPAuthError.invalidServiceAccount("PKCS#8 DER: OCTET STRING extends past end of data")
        }
        return Data(pkcs8[pkcs1Start..<pkcs1End])
    }
}

// MARK: - Models

private struct ServiceAccountJSON {
    let type: String
    let project_id: String
    let private_key_id: String
    let private_key: String
    let client_email: String
    let token_uri: String

    static func from(data: Data) throws -> ServiceAccountJSON {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GCPAuthError.invalidServiceAccount("JSON root is not an object")
        }

        func required(_ key: String) throws -> String {
            guard let value = json[key] as? String, !value.isEmpty else {
                throw GCPAuthError.invalidServiceAccount("Missing or empty key: \(key)")
            }
            return value
        }

        return ServiceAccountJSON(
            type: try required("type"),
            project_id: try required("project_id"),
            private_key_id: try required("private_key_id"),
            private_key: try required("private_key"),
            client_email: try required("client_email"),
            token_uri: try required("token_uri")
        )
    }
}

// MARK: - Errors

enum GCPAuthError: LocalizedError {
    case cannotReadServiceAccount
    case invalidServiceAccount(String)
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotReadServiceAccount:
            "Cannot read gemini-service-account.json from bundle."
        case .invalidServiceAccount(let msg):
            "GCP service account error: \(msg)"
        case .tokenExchangeFailed(let msg):
            "GCP token exchange failed: \(msg)"
        }
    }
}
