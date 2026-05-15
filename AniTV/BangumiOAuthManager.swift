//
//  BangumiOAuthManager.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import AuthenticationServices
import Combine
import SQLiteData

@MainActor
final class BangumiOAuthManager: NSObject, ObservableObject {
    static let callbackScheme = "anitv"
    static let defaultRedirectURI = "anitv://oauth/bangumi"
    static let sharedClientID = AppConfig.bangumiOAuthClientID
    static let sharedClientSecret = AppConfig.bangumiOAuthClientSecret

    @Published var isAuthenticating = false
    @Published var statusMessage = "尚未登录 Bangumi。"
    @Published var accessToken = ""
    @Published var refreshToken = ""
    @Published var rawResponse = ""
    @Published var lanServiceStatus = "局域网登录服务尚未启动。"
    @Published var lanEntryURL = ""
    @Published var lanRedirectURI = ""
    @Published var authenticatedSession: BangumiAuthenticatedSession?

    private var authenticationSession: ASWebAuthenticationSession?
    private var lanOAuthServer: BangumiLANOAuthServer?

    override init() {
        super.init()
        if let lanIPv4Address = Self.resolveLANIPv4Address() {
            lanEntryURL = "http://\(lanIPv4Address):8437/oauth/bangumi/start"
            lanRedirectURI = "http://\(lanIPv4Address):8437/oauth/bangumi"
        } else {
            lanEntryURL = ""
            lanRedirectURI = ""
            lanServiceStatus = "未能解析当前电视的局域网 IPv4 地址，二维码入口暂不可用。"
        }

        let localEndpoint = lanEntryURL.replacingOccurrences(of: "/oauth/bangumi/start", with: "")
        let server = BangumiLANOAuthServer(
            config: .init(
                clientID: Self.sharedClientID,
                clientSecret: Self.sharedClientSecret,
                redirectURI: lanRedirectURI,
                localEndpoint: localEndpoint,
                port: 8437
            ),
            onStatusChange: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.lanServiceStatus = message
                    print("[BangumiLANOAuth] \(message)")
                }
            },
            onAuthorizationCode: { [weak self] code in
                let stableCode = String(code)
                Task { @MainActor [weak self] in
                    await self?.exchangeLANCodeForToken(code: stableCode)
                }
            }
        )
        lanOAuthServer = server
        server.start()
    }

    func startLogin(
        clientID: String,
        clientSecret: String,
        redirectURI: String
    ) {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedClientID.isEmpty else {
            statusMessage = "请先填写 Bangumi client_id。"
            return
        }

        guard !normalizedClientSecret.isEmpty else {
            statusMessage = "请先填写 Bangumi client_secret。"
            return
        }

        guard !normalizedRedirectURI.isEmpty else {
            statusMessage = "请先填写 redirect_uri。"
            return
        }

        let state = UUID().uuidString

        guard let authorizationURL = Self.makeAuthorizationURL(
            clientID: normalizedClientID,
            redirectURI: normalizedRedirectURI,
            state: state
        ) else {
            statusMessage = "生成 Bangumi 授权地址失败。"
            return
        }

        guard let loginURL = Self.makeLoginRedirectURL(for: authorizationURL) else {
            statusMessage = "生成 Bangumi 登录页地址失败。"
            return
        }

        statusMessage = "正在打开 Bangumi 登录页…"
        isAuthenticating = true

        let session = ASWebAuthenticationSession(
            url: loginURL,
            callback: .customScheme(Self.callbackScheme)
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthenticating = false

                if let error {
                    self.statusMessage = "Bangumi 授权失败：\(error.localizedDescription)"
                    print("[BangumiOAuth] Authorization failed: \(error)")
                    return
                }

                guard let callbackURL else {
                    self.statusMessage = "Bangumi 没有返回回调 URL。"
                    print("[BangumiOAuth] Missing callback URL")
                    return
                }

                do {
                    let code = try self.extractAuthorizationCode(from: callbackURL, expectedState: state)
                    self.statusMessage = "已收到授权 code，正在交换 access token…"
                    let tokenResponse = try await BangumiTokenExchangeService.exchangeCodeForToken(
                        code: code,
                        clientID: normalizedClientID,
                        clientSecret: normalizedClientSecret,
                        redirectURI: normalizedRedirectURI
                    )
                    try await self.applyTokenResponse(
                        tokenResponse,
                        redirectURI: normalizedRedirectURI
                    )
                } catch {
                    self.statusMessage = error.localizedDescription
                    print("[BangumiOAuth] Callback handling failed: \(error)")
                }
            }
        }

        authenticationSession = session

        if session.start() {
            print("[BangumiOAuth] Authorization URL: \(authorizationURL.absoluteString)")
            print("[BangumiOAuth] Login URL: \(loginURL.absoluteString)")
            print("[BangumiOAuth] Started web auth session")
        } else {
            isAuthenticating = false
            statusMessage = "无法启动系统认证会话。"
            print("[BangumiOAuth] Failed to start web auth session")
        }
    }

    static func makeAuthorizationURL(
        clientID: String,
        redirectURI: String,
        state: String
    ) -> URL? {
        var components = URLComponents(url: BangumiAPI.web.build("oauth/authorize"), resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    static func makeLoginRedirectURL(for authorizationURL: URL) -> URL? {
        let referer = authorizationURL.path + (authorizationURL.query.map { "?\($0)" } ?? "")
        guard let encodedReferer = referer.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            return nil
        }
        return URL(string: BangumiAPI.web.build("login").absoluteString + "?chii_referer=" + encodedReferer)
    }

    static func makeLANState(tvEndpoint: String, sessionID: String, nonce: String) -> String? {
        makeState(
            payload: OAuthStatePayload(
                flow: .lan,
                tvEndpoint: tvEndpoint,
                sessionId: sessionID,
                nonce: nonce
            )
        )
    }

    private static func makeState(payload: OAuthStatePayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func resolveLANIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            let isRunning = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            guard isRunning, !isLoopback,
                  let addr = interface.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else { continue }
            address = String(cString: hostname)
            break
        }

        return address
    }

    private func exchangeLANCodeForToken(code: String) async {
        let stableCode = NSString(string: code) as String
        do {
            statusMessage = "局域网登录已收到 Bangumi 回调，正在交换 access token…"
            guard !lanRedirectURI.isEmpty else {
                statusMessage = "局域网登录失败：电视当前回调地址为空。"
                return
            }
            let tokenResponse = try await BangumiTokenExchangeService.exchangeCodeForToken(
                code: stableCode,
                clientID: Self.sharedClientID,
                clientSecret: Self.sharedClientSecret,
                redirectURI: lanRedirectURI
            )
            try await applyTokenResponse(
                tokenResponse,
                redirectURI: lanRedirectURI
            )
            statusMessage = "局域网登录成功"
        } catch {
            statusMessage = "局域网登录失败：\(error.localizedDescription)"
            print("[BangumiLANOAuth] Token exchange failed: \(error)")
        }
    }

    private func extractAuthorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallbackURL
        }

        let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value

        guard returnedState == expectedState else {
            throw OAuthError.stateMismatch
        }

        guard let code, !code.isEmpty else {
            throw OAuthError.missingCode
        }

        return NSString(string: code) as String
    }

    func consumeAuthenticatedSession() -> BangumiAuthenticatedSession? {
        defer { authenticatedSession = nil }
        return authenticatedSession
    }

    func refreshAccessTokenIfNeeded(
        in database: DatabaseQueue,
        refreshWindow: TimeInterval = 3 * 24 * 60 * 60,
        now: Date = Date()
    ) async {
        do {
            guard let profile = try await AniTVDatabase.currentUserProfile(in: database),
                  (profile.bgmUserID ?? 0) > 0,
                  let refreshToken = profile.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !refreshToken.isEmpty else {
                return
            }

            guard !(try await AniTVDatabase.isBangumiOAuthRefreshBlocked(in: database)) else {
                print("[BangumiOAuth] Automatic token refresh is blocked until the user logs in again")
                return
            }

            let timeUntilExpiry = profile.expiresAt.timeIntervalSince(now)
            guard timeUntilExpiry <= refreshWindow else { return }

            let redirectURIs = try await refreshRedirectURICandidates(in: database)
            print("[BangumiOAuth] Access token expires in \(timeUntilExpiry)s, starting refresh")

            var sawInvalidGrant = false
            var sawNonInvalidGrantFailure = false
            var lastError: Error?

            for redirectURI in redirectURIs {
                do {
                    let tokenResponse = try await BangumiTokenExchangeService.refreshAccessToken(
                        refreshToken: refreshToken,
                        clientID: Self.sharedClientID,
                        clientSecret: Self.sharedClientSecret,
                        redirectURI: redirectURI
                    )
                    let session = try await Self.makeAuthenticatedSession(
                        from: tokenResponse,
                        redirectURI: redirectURI
                    )

                    _ = try await AniTVDatabase.upsertCurrentUserProfile(
                        bgmUserID: session.bgmUserID,
                        username: session.username,
                        nickname: session.nickname,
                        avatar: session.avatar,
                        accessToken: session.accessToken,
                        refreshToken: session.refreshToken,
                        tokenType: session.tokenType,
                        expiresAt: session.expiresAt,
                        in: database
                    )
                    try await AniTVDatabase.setBangumiOAuthRedirectURI(redirectURI, in: database)
                    try await AniTVDatabase.setBangumiOAuthRefreshBlocked(false, in: database)

                    publish(
                        session: session,
                        tokenResponse: tokenResponse,
                        statusMessage: "Bangumi 会话已自动刷新。",
                        publishAuthenticatedSession: false
                    )
                    print("[BangumiOAuth] Access token refreshed successfully with redirect URI: \(redirectURI)")
                    return
                } catch OAuthError.invalidGrant(let response) {
                    sawInvalidGrant = true
                    lastError = OAuthError.invalidGrant(response: response)
                    print("[BangumiOAuth] Refresh attempt returned invalid_grant for redirect URI \(redirectURI): \(response)")
                } catch {
                    sawNonInvalidGrantFailure = true
                    lastError = error
                    print("[BangumiOAuth] Refresh attempt failed for redirect URI \(redirectURI): \(error)")
                }
            }

            if sawInvalidGrant, !sawNonInvalidGrantFailure {
                try await AniTVDatabase.setBangumiOAuthRefreshBlocked(true, in: database)
                statusMessage = "Bangumi 授权已失效，请重新登录。"
                print("[BangumiOAuth] Refresh token is invalid. Automatic refresh is blocked until the user logs in again.")
                return
            }

            if let lastError {
                throw lastError
            }
        } catch {
            print("[BangumiOAuth] Background token refresh failed: \(error)")
        }
    }

    private func applyTokenResponse(
        _ tokenResponse: BangumiOAuthTokenResponse,
        redirectURI: String
    ) async throws {
        let session = try await Self.makeAuthenticatedSession(
            from: tokenResponse,
            redirectURI: redirectURI
        )
        publish(
            session: session,
            tokenResponse: tokenResponse,
            statusMessage: "Bangumi 登录成功。",
            publishAuthenticatedSession: true
        )
    }

    private func publish(
        session: BangumiAuthenticatedSession,
        tokenResponse: BangumiOAuthTokenResponse,
        statusMessage: String,
        publishAuthenticatedSession: Bool
    ) {
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        rawResponse = tokenResponse.rawResponse
        self.statusMessage = statusMessage

        if publishAuthenticatedSession {
            authenticatedSession = session
        }

        print("[BangumiOAuth] access_token: \(tokenResponse.accessToken)")
        print("[BangumiOAuth] refresh_token: \(tokenResponse.refreshToken)")
        print("[BangumiOAuth] raw_response: \(tokenResponse.rawResponse)")
        print("[BangumiOAuth] user_id: \(session.bgmUserID), username: \(session.username), nickname: \(session.nickname)")
    }

    private func refreshRedirectURICandidates(in database: DatabaseQueue) async throws -> [String] {
        var redirectURIs: [String] = []

        func append(_ value: String?) {
            guard let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalizedValue.isEmpty,
                  !redirectURIs.contains(normalizedValue) else {
                return
            }
            redirectURIs.append(normalizedValue)
        }

        append(try await AniTVDatabase.bangumiOAuthRedirectURI(in: database))
        append(Self.defaultRedirectURI)
        append(lanRedirectURI)

        return redirectURIs
    }

    private static func makeAuthenticatedSession(
        from tokenResponse: BangumiOAuthTokenResponse,
        redirectURI: String
    ) async throws -> BangumiAuthenticatedSession {
        let user = try await BangumiUserService.fetchCurrentUser(accessToken: tokenResponse.accessToken)
        return BangumiAuthenticatedSession(
            bgmUserID: user.id,
            username: user.username,
            nickname: user.nickname,
            avatar: user.avatar.large ?? user.avatar.medium ?? user.avatar.small,
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            redirectURI: redirectURI
        )
    }
}

struct BangumiAuthenticatedSession: Equatable {
    let bgmUserID: Int
    let username: String
    let nickname: String
    let avatar: String?
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
    let redirectURI: String
}

private struct OAuthStatePayload: Codable {
    enum Flow: String, Codable {
        case lan
    }

    let flow: Flow
    let tvEndpoint: String?
    let sessionId: String?
    let nonce: String?
}

private struct BangumiOAuthTokenResponse {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let scope: String?
    let refreshToken: String
    let userID: Int?
    let rawResponse: String
}

private struct BangumiCurrentUser: Decodable {
    let id: Int
    let username: String
    let nickname: String
    let avatar: BangumiCurrentUserAvatar
}

private struct BangumiCurrentUserAvatar: Decodable {
    let large: String?
    let medium: String?
    let small: String?
}

private enum BangumiTokenExchangeService {
    static func exchangeCodeForToken(
        code: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> BangumiOAuthTokenResponse {
        let stableCode = NSString(string: code) as String
        let stableClientID = NSString(string: clientID) as String
        let stableClientSecret = NSString(string: clientSecret) as String
        let stableRedirectURI = NSString(string: redirectURI) as String

        let bodyString =
            "grant_type=authorization_code" +
            "&client_id=\(formURLEncode(stableClientID))" +
            "&client_secret=\(formURLEncode(stableClientSecret))" +
            "&code=\(formURLEncode(stableCode))" +
            "&redirect_uri=\(formURLEncode(stableRedirectURI))"
        return try await performTokenRequest(bodyString: bodyString)
    }

    static func refreshAccessToken(
        refreshToken: String,
        clientID: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> BangumiOAuthTokenResponse {
        let stableRefreshToken = NSString(string: refreshToken) as String
        let stableClientID = NSString(string: clientID) as String
        let stableClientSecret = NSString(string: clientSecret) as String
        let stableRedirectURI = NSString(string: redirectURI) as String

        let bodyString =
            "grant_type=refresh_token" +
            "&client_id=\(formURLEncode(stableClientID))" +
            "&client_secret=\(formURLEncode(stableClientSecret))" +
            "&refresh_token=\(formURLEncode(stableRefreshToken))" +
            "&redirect_uri=\(formURLEncode(stableRedirectURI))"
        return try await performTokenRequest(bodyString: bodyString)
    }

    private static func performTokenRequest(bodyString: String) async throws -> BangumiOAuthTokenResponse {
        var request = URLRequest(url: BangumiAPI.web.build("oauth/access_token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(bodyString.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidTokenResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let responseText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            if let oauthError = try? JSONDecoder().decode(BangumiOAuthErrorResponseWire.self, from: data),
               oauthError.error == "invalid_grant" {
                throw OAuthError.invalidGrant(response: responseText)
            }
            throw OAuthError.tokenExchangeFailed(statusCode: httpResponse.statusCode, response: responseText)
        }

        let wire = try JSONDecoder().decode(BangumiOAuthTokenResponseWire.self, from: data)
        return BangumiOAuthTokenResponse(
            accessToken: wire.accessToken,
            expiresIn: wire.expiresIn,
            tokenType: wire.tokenType,
            scope: wire.scope,
            refreshToken: wire.refreshToken,
            userID: wire.userID,
            rawResponse: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private static func formURLEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._* ")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: " ", with: "+") ?? value
    }
}

private enum BangumiUserService {
    static func fetchCurrentUser(accessToken: String) async throws -> BangumiCurrentUser {
        var request = URLRequest(url: BangumiAPI.pub.build("v0/me"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidUserResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let responseText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw OAuthError.userFetchFailed(statusCode: httpResponse.statusCode, response: responseText)
        }

        return try JSONDecoder().decode(BangumiCurrentUser.self, from: data)
    }
}

private struct BangumiOAuthTokenResponseWire: Decodable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let scope: String?
    let refreshToken: String
    let userID: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
        case refreshToken = "refresh_token"
        case userID = "user_id"
    }
}

private struct BangumiOAuthErrorResponseWire: Decodable {
    let error: String
}

private enum OAuthError: LocalizedError {
    case invalidCallbackURL
    case missingCode
    case stateMismatch
    case invalidTokenResponse
    case invalidGrant(response: String)
    case tokenExchangeFailed(statusCode: Int, response: String)
    case invalidUserResponse
    case userFetchFailed(statusCode: Int, response: String)

    var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return "Bangumi 回调 URL 无法解析。"
        case .missingCode:
            return "Bangumi 回调里没有 code。"
        case .stateMismatch:
            return "Bangumi 回调 state 校验失败。"
        case .invalidTokenResponse:
            return "Bangumi token 响应无效。"
        case .invalidGrant:
            return "Bangumi 授权已失效，请重新登录。"
        case .tokenExchangeFailed(let statusCode, let response):
            return "Bangumi token 交换失败（HTTP \(statusCode)）：\(response)"
        case .invalidUserResponse:
            return "Bangumi 用户信息响应无效。"
        case .userFetchFailed(let statusCode, let response):
            return "Bangumi 用户信息获取失败（HTTP \(statusCode)）：\(response)"
        }
    }
}
