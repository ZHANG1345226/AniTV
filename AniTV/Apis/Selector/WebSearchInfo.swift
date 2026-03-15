
import Foundation
import SwiftSoup

// Removed the old Element typealias here, now it comes from HTMLPlaceholder

struct WebSearchSubjectInfo {
    let internalId: String
    let name: String
    let fullUrl: String
    let partialUrl: String
    let origin: Element?
}

struct WebSearchChannelInfo {
    let name: String
    let content: Element
}

struct WebSearchEpisodeInfo:Codable  {
    let channel: String?
    let name: String
    let episodeSortOrEp: EpisodeSort?
    let playUrl: String
}
