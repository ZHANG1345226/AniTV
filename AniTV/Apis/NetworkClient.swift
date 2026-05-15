//
//  NetworkClient.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

/// API 基础配置
enum APIConfig {
    static let baseURL = URL(string: "https://next.bgm.tv")!
    private static let bangumiDeveloperID = "moyuwang"
    private static let bangumiAppName = "AniTV"
    private static let bangumiProjectHomepage = "https://github.com/moyuwangP/AniTV"

    static var userAgent: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"

        return "\(bangumiDeveloperID)/\(bangumiAppName)/\(version) (\(platformName)) (\(bangumiProjectHomepage))"
    }

    private static var platformName: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #else
        return "Apple"
        #endif
    }
}

/// 网络错误定义
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case badServerResponse(statusCode: Int)
    case decodingError(Error)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .badServerResponse(let code): return "服务器错误 (代码: \(code))"
        case .decodingError(let error): return "数据解析失败: \(error.localizedDescription)"
        case .unknown(let error): return "未知错误: \(error.localizedDescription)"
        }
    }
}

/// 核心网络请求客户端 (Actor 保证线程安全，或者无状态 Struct)
struct NetworkClient: Sendable {
    static let shared = NetworkClient()

    private init() {}

    func request<T: Decodable>(
        url: URL,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        try await request(T.self, method: "GET", url: url, queryItems: queryItems)
    }

    func request<T: Decodable>(
        _ type: T.Type,
        method: String,
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> T {
        let data = try await requestData(
            method: method,
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
        return try decode(type, from: data, url: url)
    }

    func get(
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> Data {
        try await requestData(
            method: "GET",
            url: url,
            queryItems: queryItems,
            headers: headers,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    func post(
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> Data {
        try await requestData(
            method: "POST",
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    func put(
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> Data {
        try await requestData(
            method: "PUT",
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    func patch(
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> Data {
        try await requestData(
            method: "PATCH",
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    func delete(
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> Data {
        try await requestData(
            method: "DELETE",
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    func requestVoid(
        method: String,
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws {
        _ = try await requestData(
            method: method,
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    func requestData(
        method: String,
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> Data {
        let response = try await send(
            method: method,
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
        return response.data
    }

    func requestResponse(
        method: String,
        url: URL,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int> = successStatusCodes
    ) async throws -> HTTPResponse {
        try await send(
            method: method,
            url: url,
            queryItems: queryItems,
            headers: headers,
            body: body,
            acceptableStatusCodes: acceptableStatusCodes
        )
    }

    private func send(
        method: String,
        url: URL,
        queryItems: [URLQueryItem]?,
        headers: [String: String],
        body: Data?,
        acceptableStatusCodes: Set<Int>
    ) async throws -> HTTPResponse {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw NetworkError.invalidURL
        }

        if let queryItems {
            components.queryItems = queryItems
        }

        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        logRequest(request)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logResponse(statusCode: nil, data: data, url: finalURL)
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        logResponse(statusCode: httpResponse.statusCode, data: data, url: finalURL)

        guard acceptableStatusCodes.contains(httpResponse.statusCode) else {
            throw NetworkError.badServerResponse(statusCode: httpResponse.statusCode)
        }

        return HTTPResponse(data: data, response: httpResponse)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        url: URL
    ) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding Error for \(url): \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    private func logRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<invalid-url>"
        print("[NetworkClient] \(method) \(url)")

        if let body = request.httpBody, !body.isEmpty {
            let preview = String(data: body, encoding: .utf8) ?? "<\(body.count) bytes>"
            print("[NetworkClient] Request Body: \(preview)")
        }
    }

    private func logResponse(statusCode: Int?, data: Data, url: URL) {
        let statusText = statusCode.map(String.init) ?? "n/a"
        print("[NetworkClient] Response \(statusText) \(url.absoluteString)")

        guard !data.isEmpty else { return }

        let preview = String(data: data.prefix(2048), encoding: .utf8) ?? "<\(data.count) bytes>"
        print("[NetworkClient] Response Body: \(preview)")
    }
}

extension NetworkClient {
    struct HTTPResponse: Sendable {
        let data: Data
        let response: HTTPURLResponse
    }

    static let successStatusCodes = Set(200...299)
}
