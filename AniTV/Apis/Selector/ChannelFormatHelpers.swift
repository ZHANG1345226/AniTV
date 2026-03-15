
import Foundation
import SwiftSoup

func isPossiblyMovie(title: String) -> Bool {
    if title == "正片" || title == "高清版" { return true }
    return title.contains("2160P") || title.contains("1440P") || title.contains("2K") || title.contains("4K") || title.contains("1080P") || title.contains("720P")
}

func convertSpecialEpisodes(name: String, raw: String?) -> EpisodeSort {
    let rawEp = raw.map { EpisodeSort($0) } ?? EpisodeSort(name)
    if case .normal = rawEp, isPossiblyMovie(title: name) {
        return EpisodeSort(1) // Movies are always episode 1
    } else {
        return rawEp
    }
}

func selectLinksOrNull(selectEpisodeLinks: String, parent: Element) -> [String]? {
    guard !selectEpisodeLinks.isEmpty else { return nil }
    guard let cssSelector = selectEpisodeLinks.toCSSSelectorOrNil() else { return nil }
    // Simulate selecting elements within the parent and extracting hrefs
    // This will need actual HTML parsing implementation from a library like SwiftSoup
    print("selectLinksOrNull: Simulating selection from parent with selector '\(cssSelector)'")
    
    // Placeholder logic for now
    if cssSelector == "a" { // Simple case for demonstration
        do {
            let url = try parent.attr("href")
            return [url]
        }catch{
            return []
        }
    }
    return ["/dummy/link/from/selectLinksOrNull/1", "/dummy/link/from/selectLinksOrNull/2"]
}

extension NSRegularExpression {
    func findGroupOrFullText(text: String, groupName: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = self.firstMatch(in: text, options: [], range: range) else { return nil }

        if let groupRange = Range(match.range(withName: groupName), in: text) {
            return String(text[groupRange])
        }
        return text // Return full text if group not found
    }
}

nonisolated
struct SelectedChannelEpisodes: Codable {
    let channels: [String]?
    let episodes: [WebSearchEpisodeInfo]
}
