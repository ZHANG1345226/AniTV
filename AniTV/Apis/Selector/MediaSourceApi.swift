import Foundation
import Combine // For potential Flow-like behavior, though direct calls are used for now

// MARK: - Core API Enums and Structs

struct FactoryId: Codable, Hashable {
    let value: String
    init(_ value: String) { self.value = value }
}

enum MediaSourceKind: String, Codable {
    case web = "WEB"
    // Add other kinds if they exist in Kotlin
}

enum MediaSourceLocation: String, Codable {
    case online = "Online"
    // Add other locations if they exist in Kotlin
}

enum MediaSourceTier: String, Codable, Comparable {
    case fallback = "Fallback"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case `default` = "Default"

    // Custom comparison for tiers
    static func < (lhs: MediaSourceTier, rhs: MediaSourceTier) -> Bool {
        let order: [MediaSourceTier] = [.fallback, .low, .medium, .default, .high]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false // Should not happen if all cases are in `order`
        }
        return lhsIndex < rhsIndex
    }
    
    init(level: Int) {
        switch level {
        case 0: self = .fallback
        case 1: self = .low
        case 2: self = .medium
        case 3: self = .default
        case 4: self = .high
        default: self = .fallback
        }
    }
}

enum ConnectionStatus: String, Codable {
    case success = "SUCCESS"
    case failed = "FAILED"
    // Assuming these can be directly mapped from ApiFailure types for convenience
    case serviceUnavailable = "SERVICE_UNAVAILABLE"
    case unauthorized = "UNAUTHORIZED"
    // Add other statuses if they exist
}

enum ApiFailure: Error {
    case networkError
    case serviceUnavailable
    case unauthorized
    case unknown(Error)
}

enum RepositoryException: Error {
    case wrapped(Error) // To wrap other errors
    case custom(String)

    // Kotlin CancellationException maps to Swift CancellationError or just rethrowing
    // For simplicity, rethrow if it's not a known RepositoryException
    static func wrapOrThrowCancellation(_ error: Error) throws -> RepositoryException {
        if error is CancellationError {
            throw error
        }
        return .wrapped(error)
    }
}

struct MediaSourceInfo: Codable {
    var displayName: String
    var description: String
    var websiteUrl: String?
    var iconUrl: String?
    var tier: Int? // User requested tier to remain Int
}

// MediaSourceArguments protocol should be defined before MediaSourceConfig uses it.
protocol MediaSourceArguments: Codable {
    var name: String { get }
    var tier: Int { get } // User requested tier to remain Int
}

struct MediaSourceConfig: Codable {
    // This will likely contain serialized arguments and other config data
    var serializedArguments: Data? // Use Data for binary serialization if applicable, or String if JSON
    var arguments: SelectorMediaSourceArguments? // Decoded arguments

    // In a real scenario, you might want a more generic way to store/retrieve arguments
    // depending on the `MediaSourceArguments` type.
    // For now, this is a simplified version focusing on `SelectorMediaSourceArguments`.

    func deserializeArgumentsOrNull<T: Decodable>(_ type: T.Type) -> T? {
        guard let serialized = serializedArguments else { return nil }
        return try? JSONDecoder().decode(type, from: serialized)
    }
}

protocol HttpMediaSource {
    // This protocol would contain HTTP-specific methods if any,
    // but the Kotlin code primarily overrides `fetch` from `MediaSource`
}

// MARK: - HTTP Client Placeholder

protocol HTTPClient: AnyObject {
    func get(url: URL) async throws -> Data
    // Add other methods as needed (e.g., post, specific headers, etc.)
}

class URLSessionHTTPClient: HTTPClient {
    func get(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // Mimic Kotlin's ClientRequestException and http status codes
        if !(200..<300).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 401 { throw ApiFailure.unauthorized }
            if httpResponse.statusCode == 503 { throw ApiFailure.serviceUnavailable }
            throw URLError(.init(rawValue: httpResponse.statusCode)) // Generic HTTP error
        }
        return data
    }
}

// MARK: - Logging Placeholder
// Simple logger, could be replaced with a more robust logging framework
struct Logger {
    func warn(message: () -> String) {
        print("WARNING: \(message())")
    }
    func info(message: () -> String) {
        print("INFO: \(message())")
    }
    func error(message: () -> String) {
        print("ERROR: \(message())")
    }
}

let logger = Logger()

// MARK: - Platform Placeholder
enum Platform {
    case desktop
    case android
    case ios
}

func currentPlatform() -> Platform {
    return .ios
}

// MARK: - Time Utilities
func currentTimeMillis() -> Int64 {
    return Int64(Date().timeIntervalSince1970 * 1000)
}

// MARK: - Concurrency Utilities (AtomicLong equivalent)
// For `AtomicLong` in Kotlin, a simple lock or DispatchQueue can be used in Swift
class AtomicLong {
    private let queue = DispatchQueue(label: "com.AniTV.AtomicLong", attributes: .concurrent)
    private var _value: Int64

    init(_ value: Int64) {
        _value = value
    }

    func load() -> Int64 {
        var result: Int64 = 0
        queue.sync { result = _value }
        return result
    }

    func compareAndSet(_ expected: Int64, _ newValue: Int64) -> Bool {
        var success = false
        queue.sync(flags: .barrier) { // Use a barrier to ensure exclusive write access
            if _value == expected {
                _value = newValue
                success = true
            }
        }
        return success
    }
}

// MARK: - Media Related

enum MatchKind: String, Codable {
    case exact = "EXACT"
    case fuzzy = "FUZZY"
}

// Media is an interface in Kotlin, so it's a protocol in Swift
protocol Media {
    var mediaId: String { get }
    var mediaSourceId: String { get }
    var originalUrl: String { get }
    var originalTitle: String { get }
}

// MARK: - DefaultMedia Placeholder
struct DefaultMedia: Codable, Media {
    var mediaId: String
    var mediaSourceId: String
    var originalUrl: String
    var download: ResourceLocation // Needs to be defined
    var originalTitle: String
    var publishedTime: Int64
    var properties: MediaProperties // Needs to be defined
    var episodeRange: EpisodeRange? // Optional to match protocol exactly
    var location: MediaSourceLocation
    var kind: MediaSourceKind
}

// MARK: - MediaProperties Placeholder
struct MediaProperties: Codable {
    var subjectName: String
    var episodeName: String
    var subtitleLanguageIds: [String]
    var resolution: Resolution
    var alliance: String
    var size: FileSize // Needs to be defined
    var subtitleKind: SubtitleKind // Needs to be defined
}

// MARK: - EpisodeRange

indirect enum EpisodeRange: Codable, Equatable {
    case empty
    case single(EpisodeSort)
    case range(start: EpisodeSort, end: EpisodeSort)
    case combined(EpisodeRange, EpisodeRange)
    case season(rawNumber: Int)

    var isKnown: Bool {
        if case .season = self { return false }
        return true
    }

    var knownSorts: [EpisodeSort] {
        switch self {
        case .empty: return []
        case .single(let value): return [value]
        case .range(let start, let end):
            guard case .normal(let startNum) = start, case .normal(let endNum) = end else {
                return [start, end]
            }
            var result: [EpisodeSort] = []
            var curr = startNum
            if start.isPartial {
                result.append(start)
                curr += 0.5
            }
            while curr < endNum {
                result.append(.normal(number: curr))
                curr += 1.0
            }
            result.append(.normal(number: endNum))
            return result
        case .combined(let first, let second):
            return first.knownSorts + second.knownSorts
        case .season: return []
        }
    }

    func isEmpty() -> Bool {
        switch self {
        case .empty: return true
        case .range(let start, let end):
            if case .normal(let startNum) = start, case .normal(let endNum) = end {
                return endNum < startNum
            }
            return false
        case .combined(let first, let second):
            return first.isEmpty() && second.isEmpty()
        default: return false
        }
    }

    static func empty() -> EpisodeRange { .empty }
//    static func single(_ value: EpisodeSort) -> EpisodeRange { .single(value) }
    static func single(_ raw: String) -> EpisodeRange { .single(EpisodeSort(raw)) }
//    static func range(start: EpisodeSort, end: EpisodeSort) -> EpisodeRange { .range(start: start, end: end) }
    static func range(start: String, end: String) -> EpisodeRange { .range(start: EpisodeSort(start), end: EpisodeSort(end)) }
    static func range(start: Int, end: Int) -> EpisodeRange { .range(start: EpisodeSort(start), end: EpisodeSort(end)) }
    static func range(_ episodes: [EpisodeSort]) -> EpisodeRange {
        return combined(episodes.map { .single($0) })
    }

//    static func combined(_ first: EpisodeRange, _ second: EpisodeRange) -> EpisodeRange {
//        if first == .empty && second == .empty { return .empty }
//        if first == .empty { return second }
//        if second == .empty { return first }
//        if first == second { return first }
//        return .combined(first, second)
//    }

    static func combined(_ list: [EpisodeRange]) -> EpisodeRange {
        guard let first = list.first else { return .empty }
        return list.dropFirst().reduce(first) { combined($0, $1) }
    }

    static func season(number: Int) -> EpisodeRange { .season(rawNumber: number) }
    static func unknownSeason() -> EpisodeRange { .season(rawNumber: -1) }

    func contains(_ expected: EpisodeSort, allowSeason: Bool = true, allowSpecial: Bool = true) -> Bool {
        if allowSeason, case .season = self { return true }
        let sorts = self.knownSorts
        if sorts.contains(expected) { return true }
        if allowSpecial, case .special(_, let expectedNum) = expected {
            return sorts.contains { sort in
                if let num = sort.number, let expectedNum = expectedNum, num == expectedNum { return true }
                return false
            }
        }
        return false
    }

    func isSingleEpisode() -> Bool {
        switch self {
        case .single: return true
        case .range(let start, let end): return start == end
        case .combined(let first, let second): return first == second
        default: return false
        }
    }

    func hasSeason() -> Bool {
        switch self {
        case .season: return true
        case .combined(let first, let second): return first.hasSeason() || second.hasSeason()
        default: return false
        }
    }
}

func + (lhs: EpisodeRange, rhs: EpisodeRange) -> EpisodeRange {
    return EpisodeRange.combined(lhs, rhs)
}

extension Optional where Wrapped == EpisodeRange {
    func orEmpty() -> EpisodeRange {
        return self ?? .empty
    }
}

// MARK: - ResourceLocation Placeholder (Sealed Class equivalent)
enum ResourceLocation: Codable {
    case webVideo(String)
}

// MARK: - FileSize Placeholder
enum FileSize: Codable {
    case unspecified
    init() { self = .unspecified }
}

// MARK: - SubtitleKind Placeholder
enum SubtitleKind: Codable {
    case embedded
    init() { self = .embedded }
}

// MARK: - WebVideoMatcher related Placeholders
protocol WebVideoMatcher {
    func `match`(url: String, context: WebVideoMatcherContext) -> WebVideoMatcherMatchResult
    func patchConfig(config: WebViewConfig) -> WebViewConfig
}

struct WebVideoMatcherContext: Codable {
    init() {}
}

enum WebVideoMatcherMatchResult {
    case loadPage
    case `continue`
    case matched(WebVideo)
}

struct WebViewConfig: Codable {
    var cookies: [String] = []
    init() {}
}

struct WebVideo: Codable {
    let url: String
    let headers: [String: String]
}

// MARK: - MediaSourceEngineHelpers Placeholder
struct MediaSourceEngineHelpers {
    static func encodeUrlSegment(_ segment: String) -> String {
        return segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
    }

    static func getSearchKeyword(_ subjectName: String, _ removeSpecial: Bool, _ useOnlyFirstWord: Bool) -> String {
        let finalName: String
        if removeSpecial {
            finalName = MediaListFilters.removeSpecials(
                subjectName,
                removeWhitespace: false,
                replaceNumbers: false,
                removeMarkers: true
            )
        } else {
            finalName = subjectName
        }

        if useOnlyFirstWord {
            if !finalName.contains(" ") {
                return finalName
            }
            let firstWord = finalName.prefix { $0 != " " }
            return firstWord.isEmpty ? finalName : String(firstWord)
        }

        return finalName
    }
}

// MARK: - LabelFirstRawTitleParser Placeholder
class LabelFirstRawTitleParser {
    func parseSubtitleLanguages(_ text: String) -> [SubtitleLanguage] {
        if text.contains("简中") { return [.chineseSimplified] }
        if text.contains("繁中") { return [.chineseTraditional] }
        return []
    }
}

// MARK: - SizedSource Placeholder
protocol SizedSource<Element> {
    associatedtype Element
    var results: [Element] { get async }
    var finished: Bool { get async }
    var totalSize: Int? { get async }
}

struct SinglePagePagedSource<T>: SizedSource {
    typealias Element = T
    let fetchBlock: () async -> [T]
    init(fetchBlock: @escaping () async -> [T]) { self.fetchBlock = fetchBlock }
    var results: [T] { get async { await fetchBlock() } }
    var finished: Bool { get async { true } }
    var totalSize: Int? { get async { nil } }
}

// MARK: - Filter Related

protocol MediaListFilterCandidate {
    var originalTitle: String { get }
    var subjectName: String { get }
    var episodeRange: EpisodeRange? { get }
}

extension DefaultMedia: MediaListFilterCandidate {
    var subjectName: String {
        return properties.subjectName
    }
}

extension WebSearchSubjectInfo: MediaListFilterCandidate {
    var originalTitle: String { name }
    var subjectName: String { name }
    var episodeRange: EpisodeRange? { nil }
}

struct MediaListFilter {
    let apply: (MediaListFilterContext, MediaListFilterCandidate) -> Bool
    func applyOn(candidate: MediaListFilterCandidate, context: MediaListFilterContext) -> Bool {
        return apply(context, candidate)
    }
    static func or(_ lhs: MediaListFilter, _ rhs: MediaListFilter) -> MediaListFilter {
        return MediaListFilter { context, candidate in
            lhs.apply(context, candidate) || rhs.apply(context, candidate)
        }
    }
}

class MediaListFilterContext {
    let subjectNames: Set<String>
    let episodeSort: EpisodeSort
    let episodeEp: EpisodeSort?
    let episodeName: String?
    init(subjectNames: Set<String>, episodeSort: EpisodeSort, episodeEp: EpisodeSort?, episodeName: String?) {
        self.subjectNames = subjectNames
        self.episodeSort = episodeSort
        self.episodeEp = episodeEp
        self.episodeName = episodeName
    }
    lazy var subjectNamesWithoutSpecial: Set<String> = {
        Set(subjectNames.map { MediaListFilters.removeSpecials($0, removeWhitespace: true, replaceNumbers: true) })
    }()
    lazy var episodeNameForCompare: String? = {
        episodeName.map { MediaListFilters.removeSpecials($0, removeWhitespace: true, replaceNumbers: true) }
    }()
}

struct MediaListFilters {
    static let ContainsSubjectName = MediaListFilter { context, media in
        let originalTitle = removeSpecials(media.subjectName, removeWhitespace: true, replaceNumbers: true)
        let matchDetails = context.subjectNamesWithoutSpecial.map { subjectName in
            let exactlyContains = originalTitle.lowercased().contains(subjectName.lowercased())
            let matchRate = StringMatcher.calculateMatchRate(originalTitle, subjectName)
            let fuzzyMatches = matchRate >= 80
            return (
                subjectName: subjectName,
                exactlyContains: exactlyContains,
                matchRate: matchRate,
                matched: exactlyContains || fuzzyMatches
            )
        }
        if let matchedDetail = matchDetails.first(where: \.matched) {
            logger.info {
                "[ContainsSubjectName] matched media='\(media.subjectName)' normalized='\(originalTitle)' subject='\(matchedDetail.subjectName)' contains=\(matchedDetail.exactlyContains) matchRate=\(matchedDetail.matchRate)"
            }
            return true
        }
        logger.info {
            let reasons = matchDetails.map { detail in
                "\(detail.subjectName): contains=\(detail.exactlyContains), matchRate=\(detail.matchRate), fuzzyMatches=\(detail.matchRate >= 80)"
            }.joined(separator: " | ")
            return "[ContainsSubjectName] not matched media='\(media.subjectName)' normalized='\(originalTitle)' reasons=[\(reasons)]"
        }
        return false
    }
    static let ContainsEpisodeSort = MediaListFilter { context, media in
        guard let range = media.episodeRange else { return false }
        return range.contains(context.episodeSort)
    }
    static let ContainsEpisodeEp = MediaListFilter { context, media in
        guard let range = media.episodeRange, let episodeEp = context.episodeEp else { return false }
        return range.contains(episodeEp)
    }
    static let ContainsEpisodeName = MediaListFilter { context, media in
        guard let episodeName = context.episodeNameForCompare, !episodeName.isEmpty else { return false }
        if case .normal = context.episodeSort { return false }
        let originalTitle = removeSpecials(media.originalTitle, removeWhitespace: true, replaceNumbers: true)
        return originalTitle.lowercased().contains(episodeName.lowercased())
    }
    static let ContainsAnyEpisodeInfo = MediaListFilter { context, media in
        ContainsEpisodeSort.applyOn(candidate: media, context: context) ||
        ContainsEpisodeName.applyOn(candidate: media, context: context) ||
        ContainsEpisodeEp.applyOn(candidate: media, context: context)
    }
    private static let numberMappings: [String: String] = [
        "X": "10", "IX": "9", "VIII": "8", "VII": "7", "VI": "6", "V": "5", "IV": "4", "III": "3", "II": "2", "I": "1",
        "十": "10", "九": "9", "八": "8", "七": "7", "六": "6", "五": "5", "四": "4", "三": "3", "二": "2", "一": "1"
    ]
    private static let minimumLength: Int = 2
    private static let charsToReplaceWithWhitespace = Set("。、，·・[]～“”~—-!@#$%^&*()_+{}|\\;':\",.<>/?【】：「」！".map { $0.unicodeScalars.first!.value })
    private static let whitespaceChars = Set(" \t\u{3000}".map { $0.unicodeScalars.first!.value })
    private struct KeepWord { let originalWord: String; let mask: String }
    private static let keepWords = [KeepWord(originalWord: "Re：", mask: "\u{E001}0\u{E002}")]
    static func removeSpecials(_ string: String, removeWhitespace: Bool, replaceNumbers: Bool, removeMarkers: Bool = false) -> String {
        var result = string
        for keepWord in keepWords { result = result.replacingOccurrences(of: keepWord.originalWord, with: keepWord.mask) }
        if removeMarkers {
            for marker in ["电影", "剧场版", "OVA", "OAD", "总集篇"] { result = result.replacingOccurrences(of: marker, with: "") }
        }
        result = applyConditionalRules(result)
        if replaceNumbers { result = replaceNumbersInString(result) }
        if removeWhitespace { result = result.unicodeScalars.filter { !whitespaceChars.contains($0.value) }.map(String.init).joined() }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        for keepWord in keepWords { result = result.replacingOccurrences(of: keepWord.mask, with: keepWord.originalWord) }
        return result
    }
    private static func applyConditionalRules(_ original: String) -> String {
        var result = ""; var nonSpecialCount = 0; var canProcess = false
        for char in original {
            let scalar = char.unicodeScalars.first!.value
            if charsToReplaceWithWhitespace.contains(scalar) {
                if nonSpecialCount == 0 || canProcess { result.append(" ") } else { result.append(char) }
            } else {
                result.append(char); nonSpecialCount += 1
                if !canProcess && nonSpecialCount >= minimumLength { canProcess = true }
            }
        }
        return result
    }
    private static func replaceNumbersInString(_ string: String) -> String {
        var result = string
        let keys = numberMappings.keys.sorted { $0.count > $1.count }
        for key in keys { result = result.replacingOccurrences(of: key, with: numberMappings[key]!) }
        return result
    }
}

struct StringMatcher {
    static func calculateMatchRate(_ s1: String, _ s2: String) -> Int {
        let len1 = s1.count; let len2 = s2.count
        if len1 == 0 || len2 == 0 { return 0 }
        var matrix = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)
        for i in 0...len1 { matrix[i][0] = i }; for j in 0...len2 { matrix[0][j] = j }
        let a1 = Array(s1); let a2 = Array(s2)
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = (a1[i-1] == a2[j-1]) ? 0 : 1
                matrix[i][j] = min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
            }
        }
        let distance = matrix[len1][len2]; let maxLen = max(len1, len2)
        return Int((1.0 - Double(distance) / Double(maxLen)) * 100.0)
    }
}

extension SelectorSearchConfig {
    func createFiltersForSubject() -> [MediaListFilter] {
        var filters: [MediaListFilter] = []
        if filterBySubjectName { filters.append(MediaListFilters.ContainsSubjectName) }
        return filters
    }
    func createFiltersForEpisode() -> [MediaListFilter] {
        var filters: [MediaListFilter] = []
        if filterByEpisodeSort { filters.append(MediaListFilters.ContainsAnyEpisodeInfo) }
        return filters
    }
}

extension Array where Element == MediaListFilter {
    func applyOn(candidate: MediaListFilterCandidate, context: MediaListFilterContext) -> Bool {
        if isEmpty { return true }
        return self.allSatisfy { $0.applyOn(candidate: candidate, context: context) }
    }
}

extension Sequence where Element: SizedSource {
    func flattenConcat(delayInBetween: TimeInterval) async -> [Element.Element] {
        var allElements: [Element.Element] = []
        for (index, source) in self.enumerated() {
            if index > 0 { try? await Task.sleep(nanoseconds: UInt64(delayInBetween * 1_000_000_000)) }
            let elements = await source.results
            allElements.append(contentsOf: elements)
        }
        return allElements
    }
}

struct Alliance: Codable, Equatable {
    let id: String
    let name: String
}

protocol MediaSource: AnyObject {
    var mediaSourceId: String { get }
    var location: MediaSourceLocation { get }
    var kind: MediaSourceKind { get }
    var info: MediaSourceInfo { get }
    func checkConnection() async -> ConnectionStatus
}

protocol MediaSourceFactory {
    var factoryId: FactoryId { get }
    var info: MediaSourceInfo { get }
    var allowMultipleInstances: Bool { get }
    func create(mediaSourceId: String, config: MediaSourceConfig, client: HTTPClient) -> MediaSource
}
