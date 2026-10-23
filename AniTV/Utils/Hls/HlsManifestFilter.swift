//
//  HlsManifestFilter.swift
//  AniTV
//
//  Created by Codex on 2026/10/24.
//  Adapted from Animeko HLS manifest ad filtering (PR #3097)
//

import Foundation

enum HlsManifestFilterStatus: Sendable {
    case filtered
    case unchanged
    case unsupported
}

struct HlsRemovedGroup: Sendable {
    let index: Int
    let lineStart: Int
    let lineEnd: Int
    let startSegmentIndex: Int
    let endSegmentIndex: Int
    let duration: Double
    let segmentCount: Int
    let reasons: [String]
}

struct HlsManifestFilterResult: Sendable {
    let status: HlsManifestFilterStatus
    let content: String
    let reason: String?
    let removedGroups: [HlsRemovedGroup]
    
    static func unchanged(_ content: String, reason: String) -> HlsManifestFilterResult {
        HlsManifestFilterResult(status: .unchanged, content: content, reason: reason, removedGroups: [])
    }
    
    static func unsupported(_ content: String, reason: String) -> HlsManifestFilterResult {
        HlsManifestFilterResult(status: .unsupported, content: content, reason: reason, removedGroups: [])
    }
}

enum HlsCandidateReason: String, Sendable {
    case strongPath = "strong_path"
    case repeatShort = "repeat_short"
    case sandwichedShort = "sandwiched_short"
    case lowDensityShort = "low_density_short"
    case sequenceIsland = "sequence_island"
    case denseTiny = "dense_tiny"
}

private struct ManifestSegment {
    let index: Int
    let duration: Double
    let uri: String
    let fileName: String
    let isDiscontinuity: Bool
    let encryptionMethod: String?
    let encryptionIv: String?
    let byteRangeHasOffset: Bool?
    let lineStart: Int
    let lineEnd: Int
}

private struct ManifestGroup {
    let index: Int
    let lineStart: Int
    let lineEnd: Int
    let startSegmentIndex: Int
    let endSegmentIndex: Int
    let duration: Double
    let count: Int
    let fileSignature: String
    let segments: [ManifestSegment]
}

enum HlsManifestFilter {
    private static let numericTsRegex = try! NSRegularExpression(pattern: #"^(.*?)(\d{1,7})\.ts$"#)
    private static let uriAttributeRegex = try! NSRegularExpression(pattern: #"(URI=")([^"]+)(")"#)
    
    /// Filters patch ads from an HLS media playlist string.
    static func filter(content: String, baseUrl: String = "http://127.0.0.1/playlist.m3u8") -> HlsManifestFilterResult {
        let lines = content.components(separatedBy: "\n")
        
        // 1. Master playlist check
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") || $0.hasPrefix("#EXT-X-I-FRAME-STREAM-INF:") }) {
            return .unsupported(content, reason: "master_playlist")
        }
        
        // 2. Media playlist endlist check
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#EXT-X-ENDLIST") }) {
            return .unsupported(content, reason: "live_or_incomplete_playlist")
        }
        
        // 3. Discontinuity check
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "#EXT-X-DISCONTINUITY" }) {
            return .unchanged(content, reason: "no_discontinuity")
        }
        
        // 4. Parse segments
        let segments = parseSegments(lines: lines)
        if segments.isEmpty {
            return .unchanged(content, reason: "no_segments")
        }
        
        // 5. Group by discontinuity
        let groups = parseGroups(segments: segments)
        if groups.isEmpty {
            return .unchanged(content, reason: "no_segments")
        }
        
        // 6. Detect candidate ad groups
        let candidates = detectCandidates(groups: groups)
        if candidates.isEmpty {
            return .unchanged(content, reason: "no_candidate")
        }
        
        // 7. Safety guards
        if segments.contains(where: { $0.encryptionMethod?.uppercased() == "AES-128" && $0.encryptionIv == nil }) {
            return .unchanged(content, reason: "encrypted_implicit_iv")
        }
        
        if segments.contains(where: { $0.byteRangeHasOffset == false }) {
            return .unchanged(content, reason: "byterange_implicit_offset")
        }
        
        let removableIndexes = Set(candidates.map { $0.group.index })
        let remainingCount = groups.filter { !removableIndexes.contains($0.index) }.reduce(0) { $0 + $1.count }
        if remainingCount == 0 {
            return .unchanged(content, reason: "all_segments_candidate")
        }
        
        // 8. Filter candidate lines
        var removedLineSet = Set<Int>()
        for candidate in candidates {
            for line in candidate.group.lineStart...candidate.group.lineEnd {
                removedLineSet.insert(line)
            }
        }
        
        var filteredLines: [String] = []
        for (idx, line) in lines.enumerated() {
            let lineNum = idx + 1
            if !removedLineSet.contains(lineNum) {
                filteredLines.append(line)
            }
        }
        
        let filteredContent = filteredLines.joined(separator: "\n")
        
        return HlsManifestFilterResult(
            status: .filtered,
            content: filteredContent,
            reason: nil,
            removedGroups: candidates.map { candidate in
                HlsRemovedGroup(
                    index: candidate.group.index,
                    lineStart: candidate.group.lineStart,
                    lineEnd: candidate.group.lineEnd,
                    startSegmentIndex: candidate.group.startSegmentIndex,
                    endSegmentIndex: candidate.group.endSegmentIndex,
                    duration: candidate.group.duration,
                    segmentCount: candidate.group.count,
                    reasons: candidate.reasons.map { $0.rawValue }
                )
            }
        )
    }
    
    private static func parseSegments(lines: [String]) -> [ManifestSegment] {
        var segments: [ManifestSegment] = []
        var currentDuration: Double? = nil
        var currentDiscontinuity = false
        var currentLineStart: Int? = nil
        var currentEncMethod: String? = nil
        var currentEncIv: String? = nil
        var currentByteRangeOffset: Bool? = nil
        
        for (idx, rawLine) in lines.enumerated() {
            let lineNum = idx + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            
            if line.hasPrefix("#") {
                if line == "#EXT-X-DISCONTINUITY" {
                    currentDiscontinuity = true
                    if currentLineStart == nil { currentLineStart = lineNum }
                } else if line.hasPrefix("#EXTINF:") {
                    let val = String(line.dropFirst("#EXTINF:".count))
                    let durStr = val.components(separatedBy: ",")[0]
                    currentDuration = Double(durStr)
                    if currentLineStart == nil { currentLineStart = lineNum }
                } else if line.hasPrefix("#EXT-X-KEY:") {
                    if currentLineStart == nil { currentLineStart = lineNum }
                    let attrs = parseAttributes(String(line.dropFirst("#EXT-X-KEY:".count)))
                    currentEncMethod = attrs["METHOD"]
                    currentEncIv = attrs["IV"]
                } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                    if currentLineStart == nil { currentLineStart = lineNum }
                    let val = String(line.dropFirst("#EXT-X-BYTERANGE:".count))
                    currentByteRangeOffset = val.contains("@")
                } else if currentDuration != nil {
                    if currentLineStart == nil { currentLineStart = lineNum }
                }
            } else if !line.isEmpty {
                if let dur = currentDuration {
                    let start = currentLineStart ?? lineNum
                    let fileName = segmentFileName(line)
                    let seg = ManifestSegment(
                        index: segments.count,
                        duration: dur,
                        uri: line,
                        fileName: fileName,
                        isDiscontinuity: currentDiscontinuity,
                        encryptionMethod: currentEncMethod,
                        encryptionIv: currentEncIv,
                        byteRangeHasOffset: currentByteRangeOffset,
                        lineStart: start,
                        lineEnd: lineNum
                    )
                    segments.append(seg)
                }
                currentDuration = nil
                currentDiscontinuity = false
                currentLineStart = nil
                currentByteRangeOffset = nil
            }
        }
        return segments
    }
    
    private static func parseGroups(segments: [ManifestSegment]) -> [ManifestGroup] {
        var groups: [ManifestGroup] = []
        var currentGroupSegs: [ManifestSegment] = []
        
        func closeGroup() {
            guard !currentGroupSegs.isEmpty else { return }
            let first = currentGroupSegs.first!
            let last = currentGroupSegs.last!
            let duration = currentGroupSegs.reduce(0.0) { $0 + $1.duration }
            let sig = currentGroupSegs.map { $0.fileName }.joined(separator: "|")
            let group = ManifestGroup(
                index: groups.count,
                lineStart: first.lineStart,
                lineEnd: last.lineEnd,
                startSegmentIndex: first.index,
                endSegmentIndex: last.index,
                duration: duration,
                count: currentGroupSegs.count,
                fileSignature: sig,
                segments: currentGroupSegs
            )
            groups.append(group)
            currentGroupSegs.removeAll()
        }
        
        for seg in segments {
            if seg.isDiscontinuity {
                closeGroup()
            }
            currentGroupSegs.append(seg)
        }
        closeGroup()
        return groups
    }
    
    private static func detectCandidates(groups: [ManifestGroup]) -> [(group: ManifestGroup, reasons: [HlsCandidateReason])] {
        let allSegments = groups.flatMap { $0.segments }
        let totalSegments = allSegments.count
        guard totalSegments > 0 else { return [] }
        
        let dense = groups.count >= 20 || Double(groups.count) / Double(totalSegments) > 0.08
        var signatureCounts: [String: Int] = [:]
        for g in groups {
            signatureCounts[g.fileSignature, default: 0] += 1
        }
        
        let sequencePrefix = dense ? numericModel(segments: allSegments) : nil
        var candidates: [(group: ManifestGroup, reasons: [HlsCandidateReason])] = []
        
        for (i, group) in groups.enumerated() {
            var reasons: [HlsCandidateReason] = []
            let previous = (i > 0) ? groups[i - 1] : nil
            let next = (i + 1 < groups.count) ? groups[i + 1] : nil
            let short = group.count <= 12 || group.duration <= 45.0
            
            let paths = group.segments.map { segmentPath($0.uri).lowercased() }.joined(separator: " ")
            let strongKeywords = ["adjump", "/ad/", "/ads/", "advert"]
            if strongKeywords.contains(where: { paths.contains($0) }) {
                reasons.append(.strongPath)
            }
            
            if (signatureCounts[group.fileSignature] ?? 0) > 1 && group.count <= 12 && group.duration <= 45.0 {
                reasons.append(.repeatShort)
            }
            
            if let prev = previous, let nxt = next,
               prev.duration >= 60.0 && nxt.duration >= 60.0 &&
               group.duration <= 45.0 && group.count >= 2 {
                reasons.append(.sandwichedShort)
            }
            
            if !dense && short && group.count >= 2 {
                reasons.append(.lowDensityShort)
            }
            
            if isSequenceIsland(dense: dense, sequencePrefix: sequencePrefix, segments: allSegments, group: group, short: short) {
                reasons.append(.sequenceIsland)
            }
            
            if dense && (group.count <= 3 || group.duration <= 12.0) && previous != nil && next != nil {
                reasons.append(.denseTiny)
            }
            
            if !reasons.isEmpty {
                var uniqueReasons: [HlsCandidateReason] = []
                for r in reasons {
                    if !uniqueReasons.contains(r) { uniqueReasons.append(r) }
                }
                candidates.append((group: group, reasons: uniqueReasons))
            }
        }
        return candidates
    }
    
    private static func isSequenceIsland(
        dense: Bool,
        sequencePrefix: String?,
        segments: [ManifestSegment],
        group: ManifestGroup,
        short: Bool
    ) -> Bool {
        guard dense, let sequencePrefix = sequencePrefix, group.count >= 2, short else {
            return false
        }
        
        let numbers = group.segments.map { trailingNumber(fileName: $0.fileName, prefix: sequencePrefix) }
        guard let first = numbers.first ?? nil, let last = numbers.last ?? nil else { return false }
        
        let prevSeg = (group.startSegmentIndex > 0) ? segments[group.startSegmentIndex - 1] : nil
        let nextSeg = (group.endSegmentIndex + 1 < segments.count) ? segments[group.endSegmentIndex + 1] : nil
        
        guard let prevNum = prevSeg.flatMap({ trailingNumber(fileName: $0.fileName, prefix: sequencePrefix) }),
              let nextNum = nextSeg.flatMap({ trailingNumber(fileName: $0.fileName, prefix: sequencePrefix) }) else {
            return false
        }
        
        let linearIsland = numbers.allSatisfy { $0 != nil } &&
            zip(numbers, numbers.dropFirst()).allSatisfy { (l, r) in
                guard let l = l, let r = r else { return false }
                return r == l + 1
            }
        
        return linearIsland &&
            nextNum == prevNum + 1 &&
            abs(first - prevNum) > 1000 &&
            abs(last - nextNum) > 1000
    }
    
    private static func numericModel(segments: [ManifestSegment]) -> String? {
        var values: [(prefix: String, num: Int)] = []
        for seg in segments {
            let nsStr = seg.fileName as NSString
            let range = NSRange(location: 0, length: nsStr.length)
            if let match = numericTsRegex.firstMatch(in: seg.fileName, options: [], range: range) {
                let prefix = nsStr.substring(with: match.range(at: 1))
                let numStr = nsStr.substring(with: match.range(at: 2))
                if let num = Int(numStr) {
                    values.append((prefix: prefix, num: num))
                }
            }
        }
        guard !values.isEmpty else { return nil }
        
        var prefixCounts: [String: Int] = [:]
        for v in values { prefixCounts[v.prefix, default: 0] += 1 }
        guard let maxPrefix = prefixCounts.max(by: { $0.value < $1.value }) else { return nil }
        guard Double(maxPrefix.value) / Double(segments.count) >= 0.8 else { return nil }
        
        let numbers = values.filter { $0.prefix == maxPrefix.key }.map { $0.num }
        let deltas = zip(numbers, numbers.dropFirst()).map { $1 - $0 }
        guard !deltas.isEmpty else { return nil }
        
        var deltaCounts: [Int: Int] = [:]
        for d in deltas { deltaCounts[d, default: 0] += 1 }
        guard let maxDelta = deltaCounts.max(by: { $0.value < $1.value }) else { return nil }
        guard maxDelta.key == 1 && Double(maxDelta.value) / Double(deltas.count) >= 0.5 else { return nil }
        
        return maxPrefix.key
    }
    
    private static func trailingNumber(fileName: String, prefix: String) -> Int? {
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(".ts") else { return nil }
        let start = fileName.index(fileName.startIndex, offsetBy: prefix.count)
        let end = fileName.index(fileName.endIndex, offsetBy: -3)
        return Int(fileName[start..<end])
    }
    
    private static func segmentFileName(_ uri: String) -> String {
        let clean = uri.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
        return clean.components(separatedBy: "/").last ?? clean
    }
    
    private static func segmentPath(_ uri: String) -> String {
        let clean = uri.components(separatedBy: "?")[0].components(separatedBy: "#")[0]
        if let url = URL(string: clean) {
            return url.path
        }
        return clean.hasPrefix("/") ? clean : "/" + clean
    }
    
    private static func parseAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = raw.components(separatedBy: ",")
        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let val = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                result[key] = val
            }
        }
        return result
    }
    
    static func rewriteMediaPlaylistUris(content: String, baseUrl: URL) -> String {
        let lines = content.components(separatedBy: "\n")
        var rewritten: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                rewritten.append(line)
            } else if trimmed.hasPrefix("#") {
                let nsLine = line as NSString
                let range = NSRange(location: 0, length: nsLine.length)
                var newLine = line
                let matches = uriAttributeRegex.matches(in: line, options: [], range: range)
                for match in matches.reversed() {
                    let p1 = nsLine.substring(with: match.range(at: 1))
                    let uri = nsLine.substring(with: match.range(at: 2))
                    let p3 = nsLine.substring(with: match.range(at: 3))
                    let resolved = URL(string: uri, relativeTo: baseUrl)?.absoluteURL.absoluteString ?? uri
                    newLine = (newLine as NSString).replacingCharacters(in: match.range, with: "\(p1)\(resolved)\(p3)")
                }
                rewritten.append(newLine)
            } else {
                let resolved = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL.absoluteString ?? trimmed
                rewritten.append(resolved)
            }
        }
        return rewritten.joined(separator: "\n")
    }
    
    static func rewriteMasterPlaylistUris(content: String, baseUrl: URL, localRouteGenerator: (URL) -> String) -> String {
        let lines = content.components(separatedBy: "\n")
        var rewritten: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                rewritten.append(line)
            } else if trimmed.hasPrefix("#EXT-X-MEDIA") || trimmed.hasPrefix("#EXT-X-I-FRAME-STREAM-INF") {
                let nsLine = line as NSString
                let range = NSRange(location: 0, length: nsLine.length)
                var newLine = line
                let matches = uriAttributeRegex.matches(in: line, options: [], range: range)
                for match in matches.reversed() {
                    let p1 = nsLine.substring(with: match.range(at: 1))
                    let uri = nsLine.substring(with: match.range(at: 2))
                    let p3 = nsLine.substring(with: match.range(at: 3))
                    let resolved = URL(string: uri, relativeTo: baseUrl)?.absoluteURL ?? URL(string: uri)!
                    let localUri = localRouteGenerator(resolved)
                    newLine = (newLine as NSString).replacingCharacters(in: match.range, with: "\(p1)\(localUri)\(p3)")
                }
                rewritten.append(newLine)
            } else if trimmed.hasPrefix("#") {
                let nsLine = line as NSString
                let range = NSRange(location: 0, length: nsLine.length)
                var newLine = line
                let matches = uriAttributeRegex.matches(in: line, options: [], range: range)
                for match in matches.reversed() {
                    let p1 = nsLine.substring(with: match.range(at: 1))
                    let uri = nsLine.substring(with: match.range(at: 2))
                    let p3 = nsLine.substring(with: match.range(at: 3))
                    let resolved = URL(string: uri, relativeTo: baseUrl)?.absoluteURL.absoluteString ?? uri
                    newLine = (newLine as NSString).replacingCharacters(in: match.range, with: "\(p1)\(resolved)\(p3)")
                }
                rewritten.append(newLine)
            } else {
                let resolved = URL(string: trimmed, relativeTo: baseUrl)?.absoluteURL ?? URL(string: trimmed)!
                let localUri = localRouteGenerator(resolved)
                rewritten.append(localUri)
            }
        }
        return rewritten.joined(separator: "\n")
    }
}
