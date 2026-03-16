
import Foundation

enum Resolution: String, Codable, CaseIterable {
    case r2160P = "2160P"
    case r1440P = "1440P"
    case r1080P = "1080P"
    case r720P = "720P"
    case r480P = "480P"
    case r360P = "360P"
    case unspecified = "Unspecified"
    
    var id: String { self.rawValue }
}

enum SubtitleLanguage: String, Codable, CaseIterable {
    case chineseSimplified = "CHS"
    case chineseTraditional = "CHT"
    case english = "EN"
    case japanese = "JA"
    case unspecified = "UND"

    var id: String { self.rawValue }
}
