//
//  BangumiBrowserTrendingParser.swift
//  AniTV
//
//  Created by Codex on 2026/4/6.
//

import Foundation
import SwiftSoup

enum BangumiBrowserTrendingParser {
    static func parse(html: String, subjectType: Int) throws -> BgmPagedResponse<TrendingSubjectDTO> {
        let document = try SwiftSoup.parse(html)
        let nodes = try document.select("#browserItemList > li").array()
        let items = try nodes.compactMap { try parseItem($0, subjectType: subjectType) }
        let total = try parseTotal(document: document, fallbackPageSize: max(nodes.count, 1), fallbackCount: items.count)
        return BgmPagedResponse(data: items, total: total)
    }

    private static func parseItem(_ node: Element, subjectType: Int) throws -> TrendingSubjectDTO? {
        let rawID = try node.id().replacingOccurrences(of: "item_", with: "")
        guard let id = Int(rawID) else { return nil }

        let titleAnchor = try node.select("h3 > a.l").first()
        let chineseTitle = try titleAnchor?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !chineseTitle.isEmpty else { return nil }

        let originalTitle = try node.select("h3 > small.grey").text().normalizedBangumiText()
        let info = try node.select("p.info").text().normalizedBangumiText()
        let rank = try node.select("span.rank").text().extractFirstInt() ?? 0
        let score = Double(try node.select("p.rateInfo > small.fade").text()) ?? 0
        let ratingTotal = try node.select("p.rateInfo > span.tip_j").text().extractFirstInt() ?? 0
        let imageURL = try node.select("img.cover").attr("src").normalizedBangumiImageURL()

        let subject = SlimSubjectDTO(
            id: id,
            name: originalTitle.isEmpty ? chineseTitle : originalTitle,
            nameCN: chineseTitle,
            type: subjectType,
            info: info,
            locked: false,
            nsfw: false,
            rating: SubjectRating(rank: rank, count: [:], score: score, total: ratingTotal),
            images: SubjectImages(
                large: imageURL,
                common: imageURL,
                medium: imageURL,
                small: imageURL,
                grid: imageURL
            )
        )

        // Legacy browser page does not expose the private API trending count.
        return TrendingSubjectDTO(count: ratingTotal, subject: subject)
    }

    private static func parseTotal(document: Document, fallbackPageSize: Int, fallbackCount: Int) throws -> Int {
        let pagerText = try document.select(".page_inner .p_edge").text()
        let numbers = pagerText.extractInts()
        if numbers.count >= 2 {
            return numbers[1] * fallbackPageSize
        }
        return fallbackCount
    }
}

private extension String {
    func normalizedBangumiText() -> String {
        replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedBangumiImageURL() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if trimmed.hasPrefix("/") {
            return BangumiAPI.web.endpoint.absoluteString + trimmed
        }
        return trimmed
    }

    func extractFirstInt() -> Int? {
        extractInts().first
    }

    func extractInts() -> [Int] {
        matches(of: /[0-9]+/).compactMap { Int(String($0.output)) }
    }
}
