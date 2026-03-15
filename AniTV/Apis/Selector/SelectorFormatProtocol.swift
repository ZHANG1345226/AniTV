
import Foundation

protocol SelectorFormat {
    var id: SelectorFormatId { get }
}

struct SelectorFormatId: Codable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }
}

protocol SelectorFormatConfig: Codable {
    func isValid() -> Bool
}

extension String {
    func toRegexOrNil() -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: self)
        } catch {
            print("Error parsing regex pattern '\(self)': \(error.localizedDescription)")
            return nil
        }
    }

    func toCSSSelectorOrNil() -> String? { // Placeholder for actual CSS selector parsing
        // In a real implementation, this would validate the CSS selector string
        return self.isEmpty ? nil : self
    }
}

struct UrlHelpers {
    static func computeAbsoluteUrl(baseUrl: String, relativeUrl: String) -> String {
        guard let baseURL = URL(string: baseUrl),
              let relativeURL = URL(string: relativeUrl) else {
            return relativeUrl // Fallback
        }
        
        // Handle cases like relativeURL being a full URL already
        if relativeURL.scheme != nil && relativeURL.host != nil {
            return relativeURL.absoluteString
        }
        
        return URL(string: relativeUrl, relativeTo: baseURL)?.absoluteString ?? relativeUrl
    }

    static func guessIdFromUrl(href: String) -> String {
        // Kotlin: href.removeSuffix("/").substringBeforeLast(".html").substringAfterLast("/")
        var processedHref = href
        if processedHref.hasSuffix("/") {
            processedHref.removeLast()
        }
        if processedHref.hasSuffix(".html") {
            processedHref = String(processedHref.dropLast(5))
        }
        return processedHref.components(separatedBy: "/").last ?? href
    }
}

typealias SelectorHelpers = UrlHelpers
