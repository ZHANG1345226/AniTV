//
//  BangumiOAuthManager.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import AuthenticationServices
import Combine

@MainActor
final class BangumiOAuthManager: NSObject, ObservableObject {
    static let callbackScheme = "anitv"
    static let defaultRedirectURI = "anitv://oauth/bangumi"
    static let sharedClientID = "bgm593869da1c4c69943"
    static let sharedClientSecret = "e6f9b56806e07e6664f9ea877afdec93"

    @Published var isAuthenticating = false
    @Published var statusMessage = "尚未登录 Bangumi。"
    @Published var accessToken = ""
    @Published var refreshToken = ""
    @Published var rawResponse = ""
    @Published var lanServiceStatus = "局域网登录服务尚未启动。"
    @Published var lanEntryURL = ""
    @Published var lanRedirectURI = ""

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
                    self.applyTokenResponse(tokenResponse)
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
            applyTokenResponse(tokenResponse)
            statusMessage = "局域网登录成功，access_token 已打印到日志和屏幕。"
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

    private func applyTokenResponse(_ tokenResponse: BangumiOAuthTokenResponse) {
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        rawResponse = tokenResponse.rawResponse
        statusMessage = "Bangumi 登录成功，access_token 已打印到日志和屏幕。"

        print("[BangumiOAuth] access_token: \(tokenResponse.accessToken)")
        print("[BangumiOAuth] refresh_token: \(tokenResponse.refreshToken)")
        print("[BangumiOAuth] raw_response: \(tokenResponse.rawResponse)")
    }
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

        var request = URLRequest(url: BangumiAPI.web.build("oauth/access_token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")

        let bodyString =
            "grant_type=authorization_code" +
            "&client_id=\(formURLEncode(stableClientID))" +
            "&client_secret=\(formURLEncode(stableClientSecret))" +
            "&code=\(formURLEncode(stableCode))" +
            "&redirect_uri=\(formURLEncode(stableRedirectURI))"
        request.httpBody = Data(bodyString.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidTokenResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let responseText = String(data: data, encoding: .utf8) ?? "<non-utf8>"
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

private enum OAuthError: LocalizedError {
    case invalidCallbackURL
    case missingCode
    case stateMismatch
    case invalidTokenResponse
    case tokenExchangeFailed(statusCode: Int, response: String)

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
        case .tokenExchangeFailed(let statusCode, let response):
            return "Bangumi token 交换失败（HTTP \(statusCode)）：\(response)"
        }
    }
}
