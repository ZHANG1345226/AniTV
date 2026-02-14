//
//  BangumiRepository.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

// 定义一个专门的 Repository 来管理 Bangumi 的数据获取
struct BangumiRepository {
    
    private let client = NetworkClient.shared
    
    /// 获取热门条目
    func fetchTrendingSubjects(
        type: Int = 2, // 2 = 动画
        limit: Int = 12,
        offset: Int = 0
    ) async throws -> TrendingResponse {
        
        let queryItems = [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        
        // 调用通用请求方法，指定返回类型为 TrendingResponse
        return try await client.request(
            url:  BangumiAPI.priv.build("p1/trending/subjects"),
            queryItems: queryItems
        )
    }
}
