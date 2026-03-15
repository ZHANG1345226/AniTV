//
//  PrivateRepository.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

// 定义一个专门的 Repository 来管理 Bangumi 的数据获取
struct PrivateRepository {
    
    private let client = NetworkClient.shared
    
    /// 获取热门条目
    func fetchTrendingSubjects() async throws -> PrivateTrendingResponse {
        
        // 调用通用请求方法，指定返回类型为 TrendingResponse
        return try await client.request(
            url:  URL(string: "http://192.168.1.15:8080/api/trending")!,
            queryItems: []
        )
    }
}
