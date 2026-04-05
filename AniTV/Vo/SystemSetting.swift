//
//  SystemSetting.swift
//  AniTV
//
//  Created by Codex on 2026/4/5.
//

import Foundation
import SQLiteData

@Table("system_settings")
nonisolated struct SystemSetting: Equatable, Identifiable {
    @Column(primaryKey: true)
    let key: String

    var value: String

    @Column("value_type")
    var valueType: String = "string"

    @Column("created_at")
    var createdAt: Date

    @Column("updated_at")
    var updatedAt: Date

    var id: String { key }
}
