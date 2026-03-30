import Foundation
import Combine
import SwiftSoup

// All other necessary imports like MediaSourceApi, WebSearchInfo, etc.

// Placeholder for Repository and Context for now, will be defined if needed
class SelectorMediaSourceEpisodeCacheRepository {
    func addCache(_ mediaSourceId: String, _ subjectName: String, _ subjectInfo: WebSearchSubjectInfo, _ episodes: [WebSearchEpisodeInfo]) {
        logger.info { "Repository: Adding cache for \(subjectName)" }
    }
}

// Corresponding to SelectorMediaSourceArguments in Kotlin
struct SelectorMediaSourceArguments: Codable, MediaSourceArguments {
    var name: String
    var description: String
    var iconUrl: String
    var searchConfig: SelectorSearchConfig
    var tier: Int

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case iconUrl
        case searchConfig
        case tier
    }

    init(
        name: String,
        description: String,
        iconUrl: String,
        searchConfig: SelectorSearchConfig,
        tier: Int
    ) {
        self.name = name
        self.description = description
        self.iconUrl = iconUrl
        self.searchConfig = searchConfig
        self.tier = tier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed Source"
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.iconUrl = try container.decodeIfPresent(String.self, forKey: .iconUrl) ?? ""
        self.searchConfig = try container.decodeIfPresent(SelectorSearchConfig.self, forKey: .searchConfig) ?? SelectorSearchConfig()
        self.tier = try container.decodeIfPresent(Int.self, forKey: .tier) ?? 0
    }

    static let `default` = SelectorMediaSourceArguments(
        name: "Selector",
        description: "",
        iconUrl: "",
        searchConfig: SelectorSearchConfig(), // Default config
        tier: 0
    )
}

// Corresponding to SelectorMediaSourceCodec in Kotlin
struct SelectorMediaSourceCodec {
    static let factoryId: FactoryId = FactoryId("web-selector")
    // In Swift, Codable handles serialization/deserialization, so a separate "Codec" class might not be necessary
    // or it would provide helper methods around JSONEncoder/Decoder.
}


// Corresponding to SelectorSearchQuery in Kotlin
struct SelectorSearchQuery {
    let subjectName: String
    let allSubjectNames: Set<String>
    let episodeSort: EpisodeSort
    let episodeEp: EpisodeSort?
    let episodeName: String?
}

// Extension to convert SelectorSearchQuery to MediaListFilterContext
extension SelectorSearchQuery {
    func toFilterContext() -> MediaListFilterContext {
        return MediaListFilterContext(
            subjectNames: allSubjectNames,
            episodeSort: episodeSort,
            episodeEp: episodeEp,
            episodeName: episodeName
        )
    }
}


// Corresponding to SelectorMediaSourceEngine in Kotlin
protocol SelectorMediaSourceEngine: AnyObject {
    func searchSubjects(searchUrl: String, subjectName: String, useOnlyFirstWord: Bool, removeSpecial: Bool) async throws -> SearchSubjectResult
    func selectSubjects(document: HTMLDocument, config: SelectorSearchConfig) -> [WebSearchSubjectInfo]?
    func searchEpisodes(subjectDetailsPageUrl: String) async throws -> HTMLDocument?
    func selectEpisodes(subjectDetailsPage: HTMLDocument, subjectUrl: String, config: SelectorSearchConfig) -> SelectedChannelEpisodes?
    func selectMedia(episodes: [WebSearchEpisodeInfo], config: SelectorSearchConfig, query: SelectorSearchQuery, mediaSourceId: String, subjectName: String) -> SelectMediaResult
    func shouldLoadPage(url: String, config: SelectorSearchConfig.MatchVideoConfig) -> Bool
    func matchWebVideo(url: String, searchConfig: SelectorSearchConfig.MatchVideoConfig) -> WebVideoMatcherMatchResult
    func doHttpGet(uri: String) async throws -> HTMLDocument
}

struct SearchSubjectResult {
    let url: URL
    let document: HTMLDocument? // nil means 404
}

struct SelectMediaResult {
    let originalList: [DefaultMedia]
    let filteredList: [DefaultMedia]
}


class DefaultSelectorMediaSourceEngine: SelectorMediaSourceEngine {
    private let client: HTTPClient
    
    init(client: HTTPClient) {
        self.client = client
    }

    private func decodeJSONStringLiteral(_ value: String) -> String? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private func normalizeHTMLContent(from data: Data) throws -> String {
        guard let rawString = String(data: data, encoding: .utf8) else {
            throw RepositoryException.custom("Failed to decode HTML content")
        }

        var normalized = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<5 {
            let looksLikeJSONStringLiteral =
                normalized.first == "\"" && normalized.last == "\""

            guard looksLikeJSONStringLiteral,
                  let decodedString = decodeJSONStringLiteral(normalized) else {
                break
            }

            normalized = decodedString
        }

        return normalized
    }

    func doHttpGet(uri: String) async throws -> HTMLDocument {
        guard let url = URL(string: uri) else { throw URLError(.badURL) }
        do {
            let data = try await client.get(url: url)
            let htmlString = try normalizeHTMLContent(from: data)
            return HTMLDocument(content: htmlString)
        } catch {
            throw try RepositoryException.wrapOrThrowCancellation(error)
        }
    }

    func searchSubjects(searchUrl: String, subjectName: String, useOnlyFirstWord: Bool, removeSpecial: Bool) async throws -> SearchSubjectResult {
        let encodedKeyword = MediaSourceEngineHelpers.encodeUrlSegment(
            MediaSourceEngineHelpers.getSearchKeyword(subjectName, removeSpecial, useOnlyFirstWord)
        )
        guard let finalUrl = URL(string: searchUrl.replacingOccurrences(of: "{keyword}", with: encodedKeyword)) else {
            throw URLError(.badURL)
        }

        do {
            let document = try await doHttpGet(uri: finalUrl.absoluteString)
            return SearchSubjectResult(url: finalUrl, document: document)
        } catch {
            // Unwrap RepositoryException if necessary
            let unwrapped: Error = (error as? RepositoryException).flatMap {
                if case .wrapped(let inner) = $0 { return inner }
                return nil
            } ?? error
            
            // Check for 404 if it's inside ApiFailure.unknown or directly URLError
            if let apiFailure = unwrapped as? ApiFailure {
                if case .networkError = apiFailure {
                    throw RepositoryException.wrapped(apiFailure)
                }
                if case .unknown(let unknownError) = apiFailure, let urlError = unknownError as? URLError, urlError.code.rawValue == 404 {
                    return SearchSubjectResult(url: finalUrl, document: nil)
                }
            }

            if let urlError = unwrapped as? URLError, urlError.code.rawValue == 404 {
                return SearchSubjectResult(url: finalUrl, document: nil)
            }
            
            if error is RepositoryException {
                throw error
            }
            throw try RepositoryException.wrapOrThrowCancellation(error)
        }
    }


    // The following `select` methods will use the placeholder logic from SelectorSubjectFormat.swift and SelectorChannelFormat.swift
    func selectSubjects(document: HTMLDocument, config: SelectorSearchConfig) -> [WebSearchSubjectInfo]? {
        var subjectFormatInstance: SelectorSubjectFormat = SelectorSubjectFormatA()
        if(config.subjectFormatId.value == "indexed"){
            subjectFormatInstance = SelectorSubjectFormatIndexed()
        }
        return subjectFormatInstance.select(document: document, baseUrl: config.finalBaseUrl, config: config.selectorSubjectFormatA)
    }

    func searchEpisodes(subjectDetailsPageUrl: String) async throws -> HTMLDocument? {
        do {
            return try await doHttpGet(uri: subjectDetailsPageUrl)
        } catch {
            let unwrapped: Error = (error as? RepositoryException).flatMap {
                if case .wrapped(let inner) = $0 { return inner }
                return nil
            } ?? error
            
            if let urlError = unwrapped as? URLError, urlError.code.rawValue == 404 {
                return nil
            }
            throw error
        }
    }

    func selectEpisodes(subjectDetailsPage: HTMLDocument, subjectUrl: String, config: SelectorSearchConfig) -> SelectedChannelEpisodes? {
        let channelFormatInstance: SelectorChannelFormat
        switch config.channelFormatId.value{
        case "index-grouped":
            channelFormatInstance = SelectorChannelFormatIndexGrouped()
            return channelFormatInstance.select(page: subjectDetailsPage, baseUrl: subjectUrl, config: config.selectorChannelFormatFlattened)
        default:
            channelFormatInstance = SelectorChannelFormatNoChannel()
            return channelFormatInstance.select(page: subjectDetailsPage, baseUrl: subjectUrl, config: config.selectorChannelFormatNoChannel)
        }
    }

    func selectMedia(episodes: [WebSearchEpisodeInfo], config: SelectorSearchConfig, query: SelectorSearchQuery, mediaSourceId: String, subjectName: String) -> SelectMediaResult {
        let parser = LabelFirstRawTitleParser()
        let originalMediaList = episodes.compactMap { info -> DefaultMedia? in
            guard let episodeSortOrEp = info.episodeSortOrEp else { return nil }

            let subtitleLanguages = guessSubtitleLanguages(info: info, parser: parser) ?? [config.defaultSubtitleLanguage.id]

            let mediaId = buildString {
                $0.append(mediaSourceId)
                $0.append(".")
                if config.selectMedia.distinguishSubjectName {
                    $0.append(subjectName)
                    $0.append("-")
                }
                if config.selectMedia.distinguishChannelName {
                    $0.append(info.channel ?? "")
                    $0.append("-")
                }
                $0.append(info.name)
                $0.append("-")
                $0.append(episodeSortOrEp.raw)
            }

            return DefaultMedia(
                mediaId: mediaId,
                mediaSourceId: mediaSourceId,
                originalUrl: info.playUrl,
                download: .webVideo(info.playUrl),
                originalTitle: config.selectMedia.distinguishSubjectName ? "\(subjectName) \(info.name)" : info.name,
                publishedTime: 0,
                properties: MediaProperties(
                    subjectName: subjectName,
                    episodeName: info.name,
                    subtitleLanguageIds: subtitleLanguages,
                    resolution: config.defaultResolution,
                    alliance: info.channel ?? "",
                    size: .unspecified,
                    subtitleKind: .embedded
                ),
                episodeRange: EpisodeRange.single(episodeSortOrEp),
                location: .online,
                kind: .web
            )
        }
        
        let filterContext = query.toFilterContext()
        let filters = config.createFiltersForEpisode()
        let filteredList = originalMediaList.filter { filters.applyOn(candidate: $0, context: filterContext) }
        
        return SelectMediaResult(originalList: originalMediaList, filteredList: filteredList)
    }

    private func guessSubtitleLanguages(info: WebSearchEpisodeInfo, parser: LabelFirstRawTitleParser) -> [String]? {
        let languagesFromChannel = info.channel.map { parser.parseSubtitleLanguages($0) } ?? []
        let languagesFromName = parser.parseSubtitleLanguages(info.name)

        let allLanguages = (languagesFromChannel + languagesFromName).map { $0.id }
        return allLanguages.isEmpty ? nil : allLanguages
    }


    func shouldLoadPage(url: String, config: SelectorSearchConfig.MatchVideoConfig) -> Bool {
        if config.enableNestedUrl {
            if let regex = config.matchNestedUrlRegex {
                let range = NSRange(url.startIndex..<url.endIndex, in: url)
                return regex.firstMatch(in: url, options: [], range: range) != nil
            }
        }
        return false
    }

    func matchWebVideo(url: String, searchConfig: SelectorSearchConfig.MatchVideoConfig) -> WebVideoMatcherMatchResult {
        if shouldLoadPage(url: url, config: searchConfig) {
            return .loadPage
        }

        guard let regex = searchConfig.matchVideoUrlRegex else { return .continue }
        let range = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let result = regex.firstMatch(in: url, options: [], range: range) else { return .continue }

        let videoUrl: String
        if let vRange = Range(result.range(withName: "v"), in: url) {
            videoUrl = String(url[vRange])
        } else {
            videoUrl = url
        }

        let headers: [String: String] = [
            "User-Agent": searchConfig.addHeadersToVideo.userAgent,
            "Referer": searchConfig.addHeadersToVideo.referer,
            "Sec-Ch-Ua-Mobile": "?0",
            "Sec-Ch-Ua-Platform": "macOS",
            "Sec-Fetch-Dest": "video",
            "Sec-Fetch-Mode": "no-cors",
            "Sec-Fetch-Site": "cross-site",
        ]

        return .matched(WebVideo(url: videoUrl, headers: headers))
    }
}


// Corresponding to SelectorMediaSource in Kotlin
class SelectorMediaSource: HttpMediaSource, MediaSource {
    let mediaSourceId: String
    private let config: MediaSourceConfig
    private let repository: SelectorMediaSourceEpisodeCacheRepository
    let kind: MediaSourceKind
    private let client: HTTPClient
    
    private let arguments: SelectorMediaSourceArguments
    private let searchConfig: SelectorSearchConfig

    private lazy var engine: DefaultSelectorMediaSourceEngine = DefaultSelectorMediaSourceEngine(client: client)

    var location: MediaSourceLocation { .online }

    init(mediaSourceId: String, config: MediaSourceConfig, repository: SelectorMediaSourceEpisodeCacheRepository, kind: MediaSourceKind = .web, client: HTTPClient) {
        self.mediaSourceId = mediaSourceId
        self.config = config
        self.repository = repository
        self.kind = kind
        self.client = client
        
        self.arguments =  config.arguments ?? SelectorMediaSourceArguments.default
        self.searchConfig = arguments.searchConfig
    }

    var info: MediaSourceInfo {
        return MediaSourceInfo(
            displayName: arguments.name,
            description: arguments.description,
            websiteUrl: searchConfig.searchUrl,
            iconUrl: arguments.iconUrl,
            tier: 0
        )
    }

    private let lastSearchTime = AtomicLong(0)

    private func delayUntilNextAllowedSearch() async {
        let interval = Int64(searchConfig.requestInterval * 1000) 
        while true {
            let now = currentTimeMillis()
            let last = lastSearchTime.load()
            let wait = (last + interval) - now
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000)) 
                continue
            }
            if lastSearchTime.compareAndSet(last, now) { return }
        }
    }

    func checkConnection() async -> ConnectionStatus {
        return await withCheckedContinuation { continuation in
            Task {
                do {
                    guard let url = URL(string: searchConfig.searchUrl) else {
                        continuation.resume(returning: .failed)
                        return
                    }
                    _ = try await client.get(url: url) 
                    continuation.resume(returning: .success)
                } catch let apiFailure as ApiFailure {
                    switch apiFailure {
                    case .networkError, .serviceUnavailable:
                        continuation.resume(returning: .failed)
                    case .unauthorized:
                        continuation.resume(returning: .unauthorized)
                    case .unknown:
                        continuation.resume(returning: .failed) 
                    }
                } catch {
                    continuation.resume(returning: .success)
                }
            }
        }
    }


    // This corresponds to the `fetch` method in Kotlin's `MediaSource`
    func fetch(query: MediaFetchRequest) async -> [MediaMatch] { 
        let allSubjectNames = Set(query.subjectNames)

        let initialSubjectNames = query.subjectNames.prefix(searchConfig.searchUseSubjectNamesCount.coerceAtLeast(1))
        
        var allMatches: [MediaMatch] = []

        for (index, name) in initialSubjectNames.enumerated() {
            if index > 0 {
                await delayUntilNextAllowedSearch()
            }
            let searchResults = await Task { () -> [DefaultMedia] in
                do {
                    // Regex for OVA
                    let regexOVA = try NSRegularExpression(pattern: ".+OVA\\s*\\d*$", options: .caseInsensitive)
                    let episodeSortForQuery: EpisodeSort = name.matches(regexOVA) ? EpisodeSort("OVA") : query.episodeSort

                    return try await self.search(
                        searchConfig: searchConfig,
                        query: SelectorSearchQuery(
                            subjectName: name,
                            allSubjectNames: allSubjectNames,
                            episodeSort: episodeSortForQuery,
                            episodeEp: query.episodeEp,
                            episodeName: query.episodeName
                        ),
                        mediaSourceId: mediaSourceId
                    )
                } catch {
                    logger.error { "Error during search for subject '\(name)': \(error)" }
                    return []
                }
            }.value

            allMatches.append(contentsOf: searchResults.map { MediaMatch(media: $0, kind: .fuzzy) })
        }
        
        return allMatches
    }

    private func search(
        searchConfig: SelectorSearchConfig,
        query: SelectorSearchQuery,
        mediaSourceId: String
    ) async throws -> [DefaultMedia] {
        await delayUntilNextAllowedSearch()

        let currentPlayerName = "avkit" 

        if !searchConfig.onlySupportsPlayers.isEmpty && !searchConfig.onlySupportsPlayers.contains(currentPlayerName) {
            logger.warn {
                "SelectorMediaSource '\(info.displayName)' is not supported by the platform player."
            }
            return []
        }

        let searchResult = try await engine.searchSubjects(
            searchUrl: searchConfig.searchUrl,
            subjectName: query.subjectName,
            useOnlyFirstWord: searchConfig.searchUseOnlyFirstWord,
            removeSpecial: searchConfig.searchRemoveSpecial
        )

        guard let document = searchResult.document else { return [] }

        guard let subjects = engine.selectSubjects(document: document, config: searchConfig) else { return [] }
        
        let filterContext = query.toFilterContext()
        let filters = searchConfig.createFiltersForSubject()
        let filteredSubjects = subjects.filter { filters.applyOn(candidate: $0, context: filterContext) }

        var allMedia: [DefaultMedia] = []
        for subjectInfo in filteredSubjects {
            guard let episodeDocument = try? await engine.doHttpGet(uri: subjectInfo.fullUrl) else { continue }
            guard let episodes = engine.selectEpisodes(subjectDetailsPage: episodeDocument, subjectUrl: subjectInfo.fullUrl, config: searchConfig)?.episodes else { continue }
            
            repository.addCache(mediaSourceId, query.subjectName, subjectInfo, episodes)
            
            let mediaResult = engine.selectMedia(
                episodes: episodes,
                config: searchConfig,
                query: query,
                mediaSourceId: mediaSourceId,
                subjectName: subjectInfo.name
            )
            
            allMedia.append(contentsOf: mediaResult.filteredList)
        }
        
        return allMedia
    }
    
    var matcher: WebVideoMatcher {
        return SelectorWebVideoMatcher(
            engine: engine,
            searchConfig: arguments.searchConfig 
        )
    }

    // Factory for SelectorMediaSource
    class Factory: MediaSourceFactory {
        let repository: SelectorMediaSourceEpisodeCacheRepository

        init(repository: SelectorMediaSourceEpisodeCacheRepository) {
            self.repository = repository
        }

        var factoryId: FactoryId { SelectorMediaSourceCodec.factoryId }

        var info: MediaSourceInfo {
            return MediaSourceInfo(
                displayName: "Selector",
                description: "通用 CSS Selector 数据源",
                iconUrl: nil 
            )
        }

        var allowMultipleInstances: Bool { true }

        func create(mediaSourceId: String, config: MediaSourceConfig, client: HTTPClient) -> MediaSource {
            return SelectorMediaSource(mediaSourceId: mediaSourceId, config: config, repository: repository, client: client)
        }
    }
}

// Helper for String buildString
func buildString(_ builder: (inout String) -> Void) -> String {
    var str = ""
    builder(&str)
    return str
}

extension Int {
    func coerceAtLeast(_ minimum: Int) -> Int {
        return Swift.max(self, minimum)
    }
}

extension Collection {
    func coerceAtLeast(_ minimum: Int) -> Int {
        return Swift.max(self.count, minimum)
    }
}

extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return self.firstMatch(in: string, options: [], range: range) != nil
    }
}

extension String {
    func matches(_ regex: NSRegularExpression) -> Bool {
        return regex.matches(self)
    }
}

// SelectorWebVideoMatcher implementation
struct SelectorWebVideoMatcher: WebVideoMatcher {
    let engine: SelectorMediaSourceEngine
    let searchConfig: SelectorSearchConfig

    func `match`(url: String, context: WebVideoMatcherContext) -> WebVideoMatcherMatchResult {
        return engine.matchWebVideo(url: url, searchConfig: searchConfig.matchVideo)
    }

    func patchConfig(config: WebViewConfig) -> WebViewConfig {
        let myCookies = searchConfig.matchVideo.cookies
        var patchedConfig = config
        patchedConfig.cookies.append(contentsOf: myCookies.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return patchedConfig
    }
}
