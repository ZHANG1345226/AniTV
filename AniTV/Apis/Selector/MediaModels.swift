
import Foundation

// Placeholder for MediaCacheMetadata. Will define later if context is provided.
struct MediaCacheMetadata: Codable {
    // Properties will be defined later
    var episodeId: String = ""
    var episodeName: String = ""
    var subjectNames: [String] = []
    var episodeSort: EpisodeSort = EpisodeSort("1") // Default to a valid EpisodeSort
}

struct MediaMatch: Codable {
    let media: DefaultMedia // Use concrete type DefaultMedia for Codable support for now
    let kind: MatchKind
}

struct ExtractionResult {
    let m3u8Url: String
    let headers: [String: String]
    let cookieString: String // 格式化为 "key1=value1; key2=value2" 方便直接塞入 Header
}

struct MediaFetchRequest: Codable {
    let subjectId: String
    let episodeId: String
    let subjectNameCN: String? // Optional
    let subjectNames: [String]
    let episodeSort: EpisodeSort
    let episodeName: String
    let episodeEp: EpisodeSort?

    // Matching the Kotlin companion object function implicitly
    func toStringMultiline() -> String {
        var result = ""
        result += "subjectId: \(subjectId)"
        result += "episodeId: \(episodeId)"
        result += "subjectNameCn: \(subjectNameCN ?? "nil")"
        result += "subjectNames:"
        subjectNames.forEach { result += "- \($0)" }
        result += "episodeSort: \(episodeSort.description)"
        result += "episodeName: \(episodeName)"
        result += "episodeEp: \(episodeEp?.description ?? "nil")"
        return result
    }

    // Infix function `matches`
    func matches(cache: MediaCacheMetadata) -> MatchKind? {
        if episodeId != "" && cache.episodeId != "" {
            if cache.episodeId == episodeId {
                return .exact
            }
            return nil
        }

        if episodeName.isNotEmpty && cache.episodeName == episodeName { return .fuzzy }

        if subjectNames.contains(where: { cache.subjectNames.contains($0) }) {
            if episodeSort == cache.episodeSort || episodeEp == cache.episodeSort {
                return .fuzzy
            } else {
                return nil
            }
        }

        return nil
    }
}

extension String {
    var isNotEmpty: Bool {
        return !self.isEmpty
    }
}
