
import Foundation
import SwiftSoup

// Make Configs conform to SelectorFormatConfig and provide isValid implementations
extension SelectorSubjectFormatAConfig: SelectorFormatConfig {
    func isValid() -> Bool {
        return !selectLists.isEmpty
    }
}

extension SelectorSubjectFormatIndexedConfig: SelectorFormatConfig {
    func isValid() -> Bool {
        return !selectNames.isEmpty && !selectLinks.isEmpty
    }
}

extension SelectorSubjectFormatJsonPathIndexedPathConfig: SelectorFormatConfig {
    func isValid() -> Bool {
        return !selectLinks.isEmpty && !selectNames.isEmpty
    }
}

// Using 'class' for SelectorSubjectFormat implementations to match Kotlin's sealed class behavior more closely,
// and allow them to be passed as objects if needed.
// 'AnyObject' constraint on protocol indicates that only class types can conform to it.
protocol SelectorSubjectFormat: AnyObject {
    var id: SelectorFormatId { get }
    func select(document: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> [WebSearchSubjectInfo]?
}

// Implementation of SelectorSubjectFormatA
class SelectorSubjectFormatA: SelectorSubjectFormat {
    let id: SelectorFormatId = SelectorFormatId("a")

    func select(document: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> [WebSearchSubjectInfo]? {
        guard let config = config as? SelectorSubjectFormatAConfig, config.isValid() else { return nil }
        
        guard let cssSelector = config.selectLists.toCSSSelectorOrNil() else { return nil }
        let elements:Elements
        do{
            elements = try document.select(cssSelector: cssSelector)
        
            let subjects = try elements.compactMap { a -> WebSearchSubjectInfo? in
                let name = try a.attr("title").isEmpty ? a.text() : a.attr("title")
                let href = try a.attr("href")
                
                guard !name.isEmpty, !href.isEmpty else { return nil }

                let id = SelectorHelpers.guessIdFromUrl(href: href)
                return WebSearchSubjectInfo(
                    internalId: id,
                    name: name,
                    fullUrl: SelectorHelpers.computeAbsoluteUrl(baseUrl: baseUrl, relativeUrl: href),
                    partialUrl: href,
                    origin: a // HTMLElement is a struct, so it's copied
                )
            }
            
            if config.preferShorterName {
                return subjects.sorted { $0.name.count < $1.name.count }
            } else {
                return subjects
            }
        }catch{
            return nil
        }
    }
}

// Implementation of SelectorSubjectFormatIndexed
class SelectorSubjectFormatIndexed: SelectorSubjectFormat {
    let id: SelectorFormatId = SelectorFormatId("indexed")

    func select(document: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> [WebSearchSubjectInfo]? {
        guard let config = config as? SelectorSubjectFormatIndexedConfig, config.isValid() else { return nil }

        guard let nameSelector = config.selectNames.toCSSSelectorOrNil(),
              let linkSelector = config.selectLinks.toCSSSelectorOrNil() else { return nil }

        let nameElements: Elements
        let linkElements: Elements
        
        do{
            nameElements = try document.select(cssSelector: nameSelector)
            linkElements = try document.select(cssSelector: linkSelector)


            let names: [String] = try nameElements.compactMap {
                let text = try $0.text().trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            let links: [String] = try linkElements.compactMap {
                let href = try $0.attr("href")
                return href.isEmpty ? nil : href
            }

            var subjects: [WebSearchSubjectInfo] = []
            for i in 0..<min(names.count, links.count) {
                let name = names[i]
                let href = links[i]
                
                let id = SelectorHelpers.guessIdFromUrl(href: href)
                subjects.append(WebSearchSubjectInfo(
                    internalId: id,
                    name: name,
                    fullUrl: SelectorHelpers.computeAbsoluteUrl(baseUrl: baseUrl, relativeUrl: href),
                    partialUrl: href,
                    origin: nil // No direct origin element for indexed approach
                ))
            }

            if config.preferShorterName {
                return subjects.sorted { $0.name.count < $1.name.count }
            } else {
                return subjects
            }
        }catch{
            return nil
        }
    }
}

// Implementation of SelectorSubjectFormatJsonPathIndexed
class SelectorSubjectFormatJsonPathIndexed: SelectorSubjectFormat {
    let id: SelectorFormatId = SelectorFormatId("json-path-indexed")

    func select(document: HTMLDocument, baseUrl: String, config: SelectorFormatConfig) -> [WebSearchSubjectInfo]? {
        guard let config = config as? SelectorSubjectFormatJsonPathIndexedPathConfig, config.isValid() else { return nil }

        // --- This section requires actual JSON parsing and JSONPath evaluation ---
        // Placeholder for now, assume document.content is JSON string.
        print("SelectorSubjectFormatJsonPathIndexed: Simulating JSON parsing for document: \(document.content.prefix(50))... with linkPath: \(config.selectLinks), namePath: \(config.selectNames)")

        // Simulate JSON parsing and JsonPath evaluation
        // Dummy data for now
        let dummyNames = ["JSON Subject 1", "JSON Subject 2"]
        let dummyHrefs = ["/json/path/1", "/json/path/2"]

        var subjects: [WebSearchSubjectInfo] = []
        for i in 0..<min(dummyNames.count, dummyHrefs.count) {
            let name = dummyNames[i]
            let href = dummyHrefs[i]

            let id = SelectorHelpers.guessIdFromUrl(href: href)
            subjects.append(WebSearchSubjectInfo(
                internalId: id,
                name: name,
                fullUrl: SelectorHelpers.computeAbsoluteUrl(baseUrl: baseUrl, relativeUrl: href),
                partialUrl: href,
                origin: nil
            ))
        }

        if config.preferShorterName {
            return subjects.sorted { $0.name.count < $1.name.count }
        } else {
            return subjects
        }
    }
}
