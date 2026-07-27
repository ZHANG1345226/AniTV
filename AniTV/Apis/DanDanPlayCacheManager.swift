//
//  DanDanPlayCacheManager.swift
//  AniTV
//
//  Created by Codex on 2026/7/27.
//

import Foundation

struct CachedBangumiData: Codable {
    let bangumi: DanDanPlayBangumi
    let lastFetchTime: Date
}

struct CachedCommentsData: Codable {
    let comments: [DanDanPlayComment]
    let fetchTime: Date
    let airDate: String?
}

struct BangumiFetchRecord: Codable {
    let lastFetchTime: Date
}

class DanDanPlayCacheManager {
    static let shared = DanDanPlayCacheManager()
    private let fileManager = FileManager.default
    private let cacheDir: URL

    private init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDir = urls[0].appendingPathComponent("DanDanPlayCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Bangumi Cache

    private func bangumiCacheURL(bgmId: Int) -> URL {
        return cacheDir.appendingPathComponent("bangumi_\(bgmId).json")
    }

    private func bangumiRecordURL(bgmId: Int) -> URL {
        return cacheDir.appendingPathComponent("bangumi_record_\(bgmId).json")
    }

    func getCachedBangumi(bgmId: Int) -> DanDanPlayBangumi? {
        let url = bangumiCacheURL(bgmId: bgmId)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedBangumiData.self, from: data) else {
            return nil
        }
        return cached.bangumi
    }

    func saveBangumi(_ bangumi: DanDanPlayBangumi, bgmId: Int) {
        let cached = CachedBangumiData(bangumi: bangumi, lastFetchTime: Date())
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: bangumiCacheURL(bgmId: bgmId))
        }
        recordBangumiFetchTime(bgmId: bgmId)
    }

    func recordBangumiFetchTime(bgmId: Int) {
        let record = BangumiFetchRecord(lastFetchTime: Date())
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: bangumiRecordURL(bgmId: bgmId))
        }
    }

    func getLastBangumiFetchTime(bgmId: Int) -> Date? {
        let recordUrl = bangumiRecordURL(bgmId: bgmId)
        if let data = try? Data(contentsOf: recordUrl),
           let record = try? JSONDecoder().decode(BangumiFetchRecord.self, from: data) {
            return record.lastFetchTime
        }
        let cacheUrl = bangumiCacheURL(bgmId: bgmId)
        if let data = try? Data(contentsOf: cacheUrl),
           let cached = try? JSONDecoder().decode(CachedBangumiData.self, from: data) {
            return cached.lastFetchTime
        }
        return nil
    }

    func isBangumiFetchThrottled(bgmId: Int) -> Bool {
        guard let lastTime = getLastBangumiFetchTime(bgmId: bgmId) else {
            return false
        }
        let elapsed = Date().timeIntervalSince(lastTime)
        return elapsed < 2 * 3600 // Within 2 hours
    }

    // MARK: - Comments Cache

    private func commentsCacheURL(episodeId: Int) -> URL {
        return cacheDir.appendingPathComponent("comments_\(episodeId).json")
    }

    func getCachedComments(episodeId: Int, airDateString: String?) -> [DanDanPlayComment]? {
        let url = commentsCacheURL(episodeId: episodeId)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedCommentsData.self, from: data) else {
            return nil
        }

        let effectiveAirDate = airDateString ?? cached.airDate
        let ttl = calculateCommentTTL(airDateString: effectiveAirDate)
        let elapsed = Date().timeIntervalSince(cached.fetchTime)

        if elapsed <= ttl {
            print("[DanDanPlayCache] Using cached comments for episode \(episodeId) (age: \(Int(elapsed))s <= ttl: \(Int(ttl))s)")
            return cached.comments
        } else {
            print("[DanDanPlayCache] Comments cache expired for episode \(episodeId) (age: \(Int(elapsed))s > ttl: \(Int(ttl))s)")
            return nil
        }
    }

    func saveComments(_ comments: [DanDanPlayComment], episodeId: Int, airDateString: String?) {
        let cached = CachedCommentsData(comments: comments, fetchTime: Date(), airDate: airDateString)
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: commentsCacheURL(episodeId: episodeId))
        }
    }

    // MARK: - TTL Calculation

    func calculateCommentTTL(airDateString: String?) -> TimeInterval {
        guard let airDate = parseAirDate(airDateString) else {
            return 24 * 3600 // default 24h fallback
        }
        let ageInSeconds = Date().timeIntervalSince(airDate)
        let day: TimeInterval = 86400

        if ageInSeconds <= 2 * day {
            return 15 * 60 // 15 min
        } else if ageInSeconds <= 7 * day {
            return 3 * 3600 // 3h
        } else if ageInSeconds <= 90 * day {
            return 6 * 3600 // 6h
        } else if ageInSeconds <= 365 * day {
            return 12 * 3600 // 12h
        } else if ageInSeconds <= 3 * 365 * day {
            return 24 * 3600 // 24h
        } else {
            return 7 * 24 * 3600 // 7 days
        }
    }

    private func parseAirDate(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = formatter.date(from: string) { return date }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]

        for fmt in formats {
            df.dateFormat = fmt
            if let date = df.date(from: string) {
                return date
            }
        }
        return nil
    }
}
