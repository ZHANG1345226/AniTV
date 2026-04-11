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
    
    // 单例模式（可选，如果不需要存储状态，直接用 static func 也可以）
    static let shared = NetworkClient()
    
    private init() {}

    /// 通用的 GET 请求方法
    /// - Parameters:
    ///   - path: API 路径，例如 "/p1/trending/subjects"
    ///   - queryItems: 查询参数，例如 [URLQueryItem(name: "type", value: "2")]
    ///   - decodingType: 返回的数据类型（必须遵守 Codable）
    func request<T: Decodable & Sendable>(
        url: URL,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> T {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw NetworkError.invalidURL
        }
        
        // 2. 如果有参数，设置给 components
        // 注意：如果有默认参数，应该在这里合并，而不是覆盖
        if let queryItems = queryItems {
            components.queryItems = queryItems
        }
        
        // 3. 关键点：从 components 中获取最终的 URL
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }
        print(finalURL)
        
        // 2. 配置 Request
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIConfig.userAgent, forHTTPHeaderField: "User-Agent")
        
        // 3. 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        print(data, response)
        
        // 4. 验证状态码
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.badServerResponse(statusCode: httpResponse.statusCode)
            }
        }
        
        // 5. 解码
        let decoder = JSONDecoder()
        // 注意：根据你提供的 JSON，key 是 "nameCN" 而不是 "name_cn"，
        // 所以这里不需要 .convertFromSnakeCase。
        // 如果其他接口有区别，可以把 decoder 作为参数传入。
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding Error for \(url): \(error)")
            throw NetworkError.decodingError(error)
        }
    }
}
