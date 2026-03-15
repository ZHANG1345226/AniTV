
import Foundation
import SwiftSoup

// For now, representing an HTML document. Will be replaced by SwiftSoup.Document later.
struct HTMLDocument {
    let content: String
    // Placeholder for selection method
    func select(cssSelector: String) throws-> Elements {
        return try SwiftSoup.parse(content).select(cssSelector)
    }
}
