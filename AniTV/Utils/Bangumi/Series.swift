//
//  Series.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/12.
//
import Foundation

func inferEpsodeCount(info:String) -> Int{
    let components = info.components(separatedBy: " / ")
    // 分割した各要素が「話数」「日付」「その他」のどれに該当するかを判定
    for component in components {
        let trimmed = component.trimmingCharacters(in: .whitespaces)
        
        // 判定1: 末尾が「话」で終わる場合は話数として処理
        if trimmed.hasSuffix("话") {
            let numberString = trimmed.replacingOccurrences(of: "话", with: "")
            if let count = Int(numberString) {
                return count
            }
        }
    }
    return 0
}

func inferFromSerieInfo(info:String) -> SerieInfo{
    
    // 日付解析用のフォーマッターを準備
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy年M月d日"
    // 解析がデバイスの地域設定に影響されないように固定
    dateFormatter.locale = Locale(identifier: "zh_CN")
    // " / " で分割する（括弧内の "連載/講談社" などが誤って分割されるのを防ぐため、スペース付きの " / " を使用します）
    let components = info.components(separatedBy: " / ")
    
    var episodeCount: Int? = nil
    var firstAiredAt: Date? = nil
    var extraComponents: [String] = []
    
    // 分割した各要素が「話数」「日付」「その他」のどれに該当するかを判定
    for component in components {
        let trimmed = component.trimmingCharacters(in: .whitespaces)
        
        // 判定1: 末尾が「话」で終わる場合は話数として処理
        if trimmed.hasSuffix("话") {
            let numberString = trimmed.replacingOccurrences(of: "话", with: "")
            if let count = Int(numberString) {
                episodeCount = count
                continue
            }
        }
        
        // 判定2: 日付のフォーマットに一致するかどうか
        if let date = dateFormatter.date(from: trimmed) {
            firstAiredAt = date
            continue
        }
        
        // 判定3: どちらにも該当しない場合はその他の情報として保持
        extraComponents.append(trimmed)
    }
    
    // 残りの情報を再び " / " で結合する
    let extraInfo = extraComponents.joined(separator: " / ")
    
    // 構造体を作成して配列に追加
    let info = SerieInfo(
        episodeCount: episodeCount,
        firstAiredAt: firstAiredAt,
        extraInfo: extraInfo
    )
    return info
}

struct SerieInfo {
    var episodeCount: Int?
    var firstAiredAt: Date?
    var extraInfo: String
    
    var isMovie: Bool {
        get {
            if episodeCount == 1{
                return true
            }else if firstAiredAt == nil && episodeCount == nil{
                return true
            }
            return false
        }
    }
    
    var isAiring: Bool{
        return true
    }
}
