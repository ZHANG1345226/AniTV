
import Foundation
import SwiftSoup

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

protocol SelectorChannelFormat: AnyObject {
    var id: SelectorFormatId { get }
    func select(page: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> SelectedChannelEpisodes?
}

// Extension to config for isValid
extension SelectorChannelFormatIndexGroupedConfig: SelectorFormatConfig {
    func isValid() -> Bool {
        return !selectChannelNames.isEmpty && !selectEpisodeLists.isEmpty && !selectEpisodesFromList.isEmpty && !matchEpisodeSortFromName.isEmpty
    }
}

class SelectorChannelFormatIndexGrouped: SelectorChannelFormat {
    let id: SelectorFormatId = SelectorFormatId("index-grouped")

    func select(page: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> SelectedChannelEpisodes? {
        guard let config = config as? SelectorChannelFormatIndexGroupedConfig, config.isValid() else { return nil }

        guard let selectChannelNames = config.selectChannelNames.toCSSSelectorOrNil() else { return nil }
        let matchChannelNameRegex = config.matchChannelName.isEmpty ? nil : config.matchChannelName.toRegexOrNil()
        guard let selectEpisodesFromList = config.selectEpisodesFromList.toCSSSelectorOrNil() else { return nil }
        guard let selectLists = config.selectEpisodeLists.toCSSSelectorOrNil() else { return nil }
        guard let matchEpisodeSortFromNameRegex = config.matchEpisodeSortFromName.toRegexOrNil() else { return nil }

        do {
            let channelNameElements = try page.select(cssSelector: selectChannelNames)
            let channelNames: [String?] = try channelNameElements.map { e in
                let text = try e.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { return nil }
                return matchChannelNameRegex?.findGroupOrFullText(text: text, groupName: "ch") ?? text
            }
            
            let lists = try page.select(cssSelector: selectLists)

            var allEpisodes: [WebSearchEpisodeInfo] = []

            for (index, listElement) in lists.enumerated() {
                guard index < channelNames.count, let channelName = channelNames[index] else { continue }
                
                let links = selectLinksOrNull(selectEpisodeLinks: config.selectEpisodeLinksFromList, parent: listElement)

                for (episodeIndex, episodeElement) in try listElement.select(selectEpisodesFromList).enumerated() {
                    let text = try episodeElement.text()
                    let href = try links?[safe: episodeIndex] ?? episodeElement.attr("href")

                    let episodeInfo = WebSearchEpisodeInfo(
                        channel: channelName,
                        name: text,
                        episodeSortOrEp: convertSpecialEpisodes(
                            name: text,
                            raw: matchEpisodeSortFromNameRegex.findGroupOrFullText(text: text, groupName: "ep")
                        ),
                        playUrl: SelectorHelpers.computeAbsoluteUrl(baseUrl: baseUrl, relativeUrl: href)
                    )
                    allEpisodes.append(episodeInfo)
                }
            }
            
            return SelectedChannelEpisodes(channels: channelNames.compactMap { $0 }, episodes: allEpisodes)
        } catch {
            return nil
        }
    }
}

// Extension to config for isValid
extension SelectorChannelFormatNoChannelConfig: SelectorFormatConfig {
    func isValid() -> Bool {
        return !selectEpisodes.isEmpty && !matchEpisodeSortFromName.isEmpty
    }
}

class SelectorChannelFormatNoChannel: SelectorChannelFormat {
    let id: SelectorFormatId = SelectorFormatId("no-channel")

    func select(page: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> SelectedChannelEpisodes? {
        guard let config = config as? SelectorChannelFormatNoChannelConfig, config.isValid() else { return nil }

        guard let matchEpisodeSortFromNameRegex = config.matchEpisodeSortFromName.toRegexOrNil() else { return nil }
        guard let selectEpisodes = config.selectEpisodes.toCSSSelectorOrNil() else { return nil }

        do {
            // Simulating parent for selectLinksOrNull; in real scenario, 'page' would be the parent.
            let doc = try SwiftSoup.parse(page.content)
            guard let body = doc.body() else {
                logger.warn(message: { "No body element found while selecting no-channel episodes." })
                return nil
            }
            let links = selectLinksOrNull(selectEpisodeLinks: config.selectEpisodeLinks, parent: body)

            var episodes: [WebSearchEpisodeInfo] = []
            for (index, episodeElement) in try page.select(cssSelector: selectEpisodes).enumerated() {
                let text = try episodeElement.text()
                let href = try links?[safe: index] ?? episodeElement.attr("href")

                let episodeInfo = WebSearchEpisodeInfo(
                    channel: nil,
                    name: text,
                    episodeSortOrEp: convertSpecialEpisodes(
                        name: text,
                        raw: matchEpisodeSortFromNameRegex.findGroupOrFullText(text: text, groupName: "ep")
                    ),
                    playUrl: SelectorHelpers.computeAbsoluteUrl(baseUrl: baseUrl, relativeUrl: href)
                )
                episodes.append(episodeInfo)
            }
            
            return SelectedChannelEpisodes(channels: nil, episodes: episodes)
        } catch {
            return nil
        }
    }
}
