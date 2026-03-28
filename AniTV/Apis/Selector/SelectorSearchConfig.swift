
import Foundation

// Placeholder structs for format configs, these will be filled in when their respective
// formats are translated.
struct SelectorSubjectFormatAConfig: Codable {
    var selectLists: String = "div.video-info-header > a"
    var preferShorterName: Bool = true
}

struct SelectorSubjectFormatIndexedConfig: Codable {
    var selectNames: String = ".search-box .thumb-content > .thumb-txt"
    var selectLinks: String = ".search-box .thumb-menu > a"
    var preferShorterName: Bool = true
}

struct SelectorSubjectFormatJsonPathIndexedPathConfig: Codable {
    var selectLinks: String = "$[*]['url', 'link']"
    var selectNames: String = "$[*]['title','name']"
    var preferShorterName: Bool = true
}

struct SelectorChannelFormatIndexGroupedConfig: Codable {
    var selectChannelNames: String = ".anthology-tab > .swiper-wrapper a"
    var matchChannelName: String = """
^(?<ch>.+?)(\\d+)?$
"""
    var selectEpisodeLists: String = ".anthology-list-box"
    var selectEpisodesFromList: String = "a"
    var selectEpisodeLinksFromList: String = ""
    var matchEpisodeSortFromName: String = "第\\s*(?<ep>.+)\\s*[话集]"
}

struct SelectorChannelFormatNoChannelConfig: Codable {
    var selectEpisodes: String = "#glist-1 > div.module-blocklist.scroll-box.scroll-box-y > div > a"
    var selectEpisodeLinks: String = ""
    var matchEpisodeSortFromName: String = "第\\s*(?<ep>.+)\\s*[话集]"
}


struct SelectorSearchConfig: Codable {
    // Phase 1, search
    var searchUrl: String = "" // required
    var searchUseOnlyFirstWord: Bool = true
    var searchRemoveSpecial: Bool = true
    var searchUseSubjectNamesCount: Int = 1
    var rawBaseUrl: String = ""
    var requestInterval: TimeInterval = 3.0 // Default 3 seconds, Kotlin's 3.seconds

    // Phase 2, for search result, select subjects
    var subjectFormatId: SelectorFormatId = SelectorFormatId("a")
    var selectorSubjectFormatA: SelectorSubjectFormatAConfig = SelectorSubjectFormatAConfig()
    var selectorSubjectFormatIndexed: SelectorSubjectFormatIndexedConfig = SelectorSubjectFormatIndexedConfig()
    var selectorSubjectFormatJsonPathIndexed: SelectorSubjectFormatJsonPathIndexedPathConfig = SelectorSubjectFormatJsonPathIndexedPathConfig()

    // Phase 3, for each subject, select channels
    var channelFormatId: SelectorFormatId = SelectorFormatId("no-channel")
    var selectorChannelFormatFlattened: SelectorChannelFormatIndexGroupedConfig = SelectorChannelFormatIndexGroupedConfig()
    var selectorChannelFormatNoChannel: SelectorChannelFormatNoChannelConfig = SelectorChannelFormatNoChannelConfig()

    var defaultResolution: Resolution = .r1080P
    var defaultSubtitleLanguage: SubtitleLanguage = .chineseSimplified
    var onlySupportsPlayers: [String] = []

    // Search done. Now we should have Medias.
    var filterByEpisodeSort: Bool = true
    var filterBySubjectName: Bool = true

    // When playing a media:
    var selectMedia: SelectMediaConfig = SelectMediaConfig()
    var matchVideo: MatchVideoConfig = MatchVideoConfig()

    // Lazily computed property for finalBaseUrl
    var finalBaseUrl: String {
        if !rawBaseUrl.isEmpty {
            return rawBaseUrl
        }
        return Self.guessBaseUrl(searchUrl)
    }

    struct MatchVideoConfig: Codable {
        var enableNestedUrl: Bool = true
        var matchNestedUrl: String = """
^.+(m3u8|vip|xigua\\.php).+\\?
"""
        var matchVideoUrl: String = "(^http(s)?:\\/\\/(?!.*http(s)?:\\/\\/).+((\\.mp4)|(\\.mkv)|(m3u8)).*(\\?.+)?)|(akamaized)|(bilivideo.com)"
        var cookies: String = "quality=1080"
        var addHeadersToVideo: VideoHeaders = VideoHeaders()

        var matchNestedUrlRegex: NSRegularExpression? {
            return matchNestedUrl.toRegexOrNil()
        }
        var matchVideoUrlRegex: NSRegularExpression? {
            return matchVideoUrl.toRegexOrNil()
        }
    }

    struct VideoHeaders: Codable {
        var referer: String = ""
        var userAgent: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"

        enum CodingKeys: String, CodingKey {
            case referer
            case userAgent
        }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.referer = try container.decodeIfPresent(String.self, forKey: .referer) ?? ""
            self.userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent) ?? "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
        }
    }

    struct SelectMediaConfig: Codable {
        var distinguishSubjectName: Bool = true
        var distinguishChannelName: Bool = true
    }

    // Static helper functions
    static func guessBaseUrl(_ searchUrl: String) -> String {
        guard let url = URL(string: searchUrl) else { return searchUrl.trimmingCharacters(in: .init(charactersIn: "/")) }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        
        return components?.url?.absoluteString.trimmingCharacters(in: .init(charactersIn: "/")) ?? searchUrl.trimmingCharacters(in: .init(charactersIn: "/"))
    }

    // Custom CodingKeys and init/encode for requestInterval to handle milliseconds
    enum CodingKeys: String, CodingKey {
        case searchUrl
        case searchUseOnlyFirstWord
        case searchRemoveSpecial
        case searchUseSubjectNamesCount
        case rawBaseUrl
        case requestInterval
        case subjectFormatId
        case selectorSubjectFormatA
        case selectorSubjectFormatIndexed
        case selectorSubjectFormatJsonPathIndexed
        case channelFormatId
        case selectorChannelFormatFlattened
        case selectorChannelFormatNoChannel
        case defaultResolution
        case defaultSubtitleLanguage
        case onlySupportsPlayers
        case filterByEpisodeSort
        case filterBySubjectName
        case selectMedia
        case matchVideo
    }

    init() {
        // Default initializer for when no decoding is needed, just to satisfy `Codable` requirements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.searchUrl = try container.decodeIfPresent(String.self, forKey: .searchUrl) ?? ""
        self.searchUseOnlyFirstWord = try container.decodeIfPresent(Bool.self, forKey: .searchUseOnlyFirstWord) ?? true
        self.searchRemoveSpecial = try container.decodeIfPresent(Bool.self, forKey: .searchRemoveSpecial) ?? true
        self.searchUseSubjectNamesCount = try container.decodeIfPresent(Int.self, forKey: .searchUseSubjectNamesCount) ?? 1
        self.rawBaseUrl = try container.decodeIfPresent(String.self, forKey: .rawBaseUrl) ?? ""
        
        // Decode requestInterval from milliseconds
        let requestIntervalMillis = try container.decodeIfPresent(Double.self, forKey: .requestInterval) ?? 3000.0
        self.requestInterval = requestIntervalMillis / 1000.0 // Convert to seconds
        
        self.subjectFormatId = try container.decodeIfPresent(SelectorFormatId.self, forKey: .subjectFormatId) ?? SelectorFormatId("a")
        self.selectorSubjectFormatA = try container.decodeIfPresent(SelectorSubjectFormatAConfig.self, forKey: .selectorSubjectFormatA) ?? SelectorSubjectFormatAConfig()
        self.selectorSubjectFormatIndexed = try container.decodeIfPresent(SelectorSubjectFormatIndexedConfig.self, forKey: .selectorSubjectFormatIndexed) ?? SelectorSubjectFormatIndexedConfig()
        self.selectorSubjectFormatJsonPathIndexed = try container.decodeIfPresent(SelectorSubjectFormatJsonPathIndexedPathConfig.self, forKey: .selectorSubjectFormatJsonPathIndexed) ?? SelectorSubjectFormatJsonPathIndexedPathConfig()
        self.channelFormatId = try container.decodeIfPresent(SelectorFormatId.self, forKey: .channelFormatId) ?? SelectorFormatId("no-channel")
        self.selectorChannelFormatFlattened = try container.decodeIfPresent(SelectorChannelFormatIndexGroupedConfig.self, forKey: .selectorChannelFormatFlattened) ?? SelectorChannelFormatIndexGroupedConfig()
        self.selectorChannelFormatNoChannel = try container.decodeIfPresent(SelectorChannelFormatNoChannelConfig.self, forKey: .selectorChannelFormatNoChannel) ?? SelectorChannelFormatNoChannelConfig()
        self.defaultResolution = try container.decodeIfPresent(Resolution.self, forKey: .defaultResolution) ?? .r1080P
        self.defaultSubtitleLanguage = try container.decodeIfPresent(SubtitleLanguage.self, forKey: .defaultSubtitleLanguage) ?? .chineseSimplified
        self.onlySupportsPlayers = try container.decodeIfPresent([String].self, forKey: .onlySupportsPlayers) ?? []
        self.filterByEpisodeSort = try container.decodeIfPresent(Bool.self, forKey: .filterByEpisodeSort) ?? true
        self.filterBySubjectName = try container.decodeIfPresent(Bool.self, forKey: .filterBySubjectName) ?? true
        self.selectMedia = try container.decodeIfPresent(SelectMediaConfig.self, forKey: .selectMedia) ?? SelectMediaConfig()
        self.matchVideo = try container.decodeIfPresent(MatchVideoConfig.self, forKey: .matchVideo) ?? MatchVideoConfig()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchUrl, forKey: .searchUrl)
        try container.encode(searchUseOnlyFirstWord, forKey: .searchUseOnlyFirstWord)
        try container.encode(searchRemoveSpecial, forKey: .searchRemoveSpecial)
        try container.encode(searchUseSubjectNamesCount, forKey: .searchUseSubjectNamesCount)
        try container.encode(rawBaseUrl, forKey: .rawBaseUrl)
        
        // Encode requestInterval to milliseconds
        try container.encode(requestInterval * 1000.0, forKey: .requestInterval) // Convert to milliseconds
        
        try container.encode(subjectFormatId, forKey: .subjectFormatId)
        try container.encode(selectorSubjectFormatA, forKey: .selectorSubjectFormatA)
        try container.encode(selectorSubjectFormatIndexed, forKey: .selectorSubjectFormatIndexed)
        try container.encode(selectorSubjectFormatJsonPathIndexed, forKey: .selectorSubjectFormatJsonPathIndexed)
        try container.encode(channelFormatId, forKey: .channelFormatId)
        try container.encode(selectorChannelFormatFlattened, forKey: .selectorChannelFormatFlattened)
        try container.encode(selectorChannelFormatNoChannel, forKey: .selectorChannelFormatNoChannel)
        try container.encode(defaultResolution, forKey: .defaultResolution)
        try container.encode(defaultSubtitleLanguage, forKey: .defaultSubtitleLanguage)
        try container.encode(onlySupportsPlayers, forKey: .onlySupportsPlayers)
        try container.encode(filterByEpisodeSort, forKey: .filterByEpisodeSort)
        try container.encode(filterBySubjectName, forKey: .filterBySubjectName)
        try container.encode(selectMedia, forKey: .selectMedia)
        try container.encode(matchVideo, forKey: .matchVideo)
    }
}
