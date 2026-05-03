//
//  UserProfile.swift
//  AniTV
//
//  Created by Codex on 2026/5/3.
//

import Foundation
import SQLiteData

@Table("user_profiles")
nonisolated struct UserProfile: Equatable, Identifiable {
    let id: Int

    @Column("bgm_user_id")
    var bgmUserID: Int?

    var username: String?
    var nickname: String?
    var avatar: String?

    @Column("access_token")
    var accessToken: String?

    @Column("refresh_token")
    var refreshToken: String?

    @Column("token_type")
    var tokenType: String?

    @Column("last_used_at")
    var lastUsedAt: Date

    @Column("expires_at")
    var expiresAt: Date

    @Column("created_at")
    var createdAt: Date

    @Column("updated_at")
    var updatedAt: Date

    var isAuthenticated: Bool {
        guard let bgmUserID, accessToken != nil else { return false }
        return bgmUserID > 0 && expiresAt > Date()
    }

    var effectiveBgmUserID: Int? {
        isAuthenticated ? bgmUserID : nil
    }

    var effectiveUsername: String? {
        isAuthenticated ? username : nil
    }

    var effectiveAvatar: String? {
        isAuthenticated ? avatar : nil
    }

    var effectiveNickname: String {
        guard isAuthenticated, let nickname, !nickname.isEmpty else {
            return "Guest"
        }
        return nickname
    }
}
