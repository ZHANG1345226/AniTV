//
//  Request.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/2/11.
//

import Foundation

enum BangumiAPI {
  case pub
  case priv
  case web

  var endpoint: URL {
    switch self {
    case .pub:
      return URL(string: "https://api.bgm.tv")!
    case .priv:
      return URL(string: "https://next.bgm.tv")!
    case .web:
      return URL(string: "https://bgm.tv")!
    }
  }

  func build(_ path: String) -> URL {
    return self.endpoint.appendingPathComponent(path)
  }
}
