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

    @Test func hlsManifestFilterAdDetection() throws {
        // Build simulated low-density playlist with sandwiched ad
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:5",
            "#EXT-X-MEDIA-SEQUENCE:0"
        ]
        
        // Group 0: 30 segments of 3s = 90s
        for i in 0..<30 {
            lines.append("#EXTINF:3.000000,")
            lines.append("main_seg_\(i).ts")
        }
        
        // Group 1 (Ad): 5 segments of 4s = 20s
        lines.append("#EXT-X-DISCONTINUITY")
        for i in 0..<5 {
            lines.append("#EXTINF:4.000000,")
            lines.append("ad_seg_\(i).ts")
        }
        
        // Group 2: 30 segments of 3s = 90s
        lines.append("#EXT-X-DISCONTINUITY")
        for i in 30..<60 {
            lines.append("#EXTINF:3.000000,")
            lines.append("main_seg_\(i).ts")
        }
        lines.append("#EXT-X-ENDLIST")
        
        let content = lines.joined(separator: "\n")
        let result = HlsManifestFilter.filter(content: content)
        
        #expect(result.status == .filtered)
        #expect(result.removedGroups.count == 1)
        #expect(result.removedGroups.first?.segmentCount == 5)
        #expect(!result.content.contains("ad_seg_"))
        #expect(result.content.contains("main_seg_0.ts"))
        #expect(result.content.contains("main_seg_59.ts"))
    }

    @Test func hlsManifestFilterMasterPlaylistUnsupported() throws {
        let masterContent = """
        #EXTM3U
        #EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=800000,RESOLUTION=1080x608
        2000k/hls/index.m3u8
        """
        let result = HlsManifestFilter.filter(content: masterContent)
        #expect(result.status == .unsupported)
        #expect(result.reason == "master_playlist")
    }

    @Test func hlsManifestFilterLivePlaylistUnsupported() throws {
        let liveContent = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXTINF:4.0,
        seg1.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:4.0,
        seg2.ts
        """
        let result = HlsManifestFilter.filter(content: liveContent)
        #expect(result.status == .unsupported)
        #expect(result.reason == "live_or_incomplete_playlist")
    }

    @Test func hlsManifestFilterImplicitIvUnchanged() throws {
        let content = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
        #EXTINF:100.0,
        main1.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:10.0,
        ad1.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:100.0,
        main2.ts
        #EXT-X-ENDLIST
        """
        let result = HlsManifestFilter.filter(content: content)
        #expect(result.status == .unchanged)
        #expect(result.reason == "encrypted_implicit_iv")
    }
}
