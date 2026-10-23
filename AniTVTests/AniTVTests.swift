//
//  AniTVTests.swift
//  AniTVTests
//
//  Created by Feiran Yang on 2026/2/10.
//

import Foundation
import Testing
@testable import AniTV

struct AniTVTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func timelineServiceDemo() async throws {
        let database = try AniTVDatabase.makeDefaultDatabase()

        if try await AniTVDatabase.isBangumiDataEmpty(in: database) {
            let release = try await AniTVDatabase.resolveBangumiDataRelease()
            let items = try await AniTVDatabase.downloadBangumiData(from: release.url)
            try await AniTVDatabase.replaceBangumiData(items, version: release.version, in: database)
        }

        let service = TimelineService()
        let timeline = try await service.fetchTimelineMap(
            database: database,
            now: Date(),
            daysBefore: 7,
            daysAfter: 7
        )

        let sortedKeys = timeline.keys.sorted()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm:ss"

        var orderedEntries: [[String: Any]] = []
        for key in sortedKeys {
            let entries = timeline[key, default: []]
            for entry in entries {
                let formattedTime: String
                if entry.airingTimestamp == .max {
                    formattedTime = "unknown"
                } else {
                    let date = Date(timeIntervalSince1970: TimeInterval(entry.airingTimestamp))
                    formattedTime = timeFormatter.string(from: date)
                }

                orderedEntries.append([
                    "date": key,
                    "time": formattedTime,
                    "airingTimestamp": entry.airingTimestamp,
                    "subjectTitle": entry.subjectTitle,
                    "subjectTitleCN": entry.subjectTitleCN as Any,
                    "episodeSort": entry.episodeSort as Any,
                    "episodeName": entry.episodeName as Any,
                    "episodeNameCN": entry.episodeNameCN as Any,
                    "bangumiID": entry.bangumiID as Any,
                    "anilistID": entry.anilistID as Any,
                    "isAniListMissing": entry.isAniListMissing,
                    "coverImageURL": entry.coverImageURL as Any
                ])
            }
        }

        let payload: [String: Any] = [
            "dayCount": timeline.count,
            "days": sortedKeys,
            "entries": orderedEntries
        ]

        let jsonData = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }

        #expect(!timeline.isEmpty)
    }

}
