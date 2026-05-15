//
//  Config.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/27.
//

import Foundation

enum MediaSourceConfigLoader {
    static let defaultSubscriptionURL = URL(string: "https://sub.creamycake.org/v1/css1.json")!

    static func downloadResponse(from url: URL) async throws -> MediaSourceResponse {
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 60
            configuration.waitsForConnectivity = false
            return configuration
        }())

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw MediaSourceConfigLoaderError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(MediaSourceResponse.self, from: data)
        } catch let decodingError as DecodingError {
            logDecodingError(decodingError)
            throw decodingError
        } catch {
            throw error
        }
    }

    static func makeArgumentsJSONString(from arguments: SelectorMediaSourceArguments) throws -> String {
        let data = try JSONEncoder().encode(arguments)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MediaSourceConfigLoaderError.encodingFailed
        }
        return string
    }

    private static func logDecodingError(_ error: DecodingError) {
        switch error {
        case .keyNotFound(let key, let context):
            print("[MediaSourceConfigLoader] keyNotFound \(key.stringValue), path: \(formatCodingPath(context.codingPath))")
        case .valueNotFound(let type, let context):
            print("[MediaSourceConfigLoader] valueNotFound \(type), path: \(formatCodingPath(context.codingPath))")
        case .typeMismatch(let type, let context):
            print("[MediaSourceConfigLoader] typeMismatch \(type), path: \(formatCodingPath(context.codingPath)), reason: \(context.debugDescription)")
        case .dataCorrupted(let context):
            print("[MediaSourceConfigLoader] dataCorrupted, path: \(formatCodingPath(context.codingPath)), reason: \(context.debugDescription)")
        @unknown default:
            print("[MediaSourceConfigLoader] unknown decoding error: \(error)")
        }
    }

    private static func formatCodingPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "<root>" }
        return codingPath
            .map { key in
                if let intValue = key.intValue {
                    return "[\(intValue)]"
                }
                return key.stringValue
            }
            .joined(separator: ".")
    }
}

struct MediaSourceResponse: Codable {
    let exportedMediaSourceDataList: ExportedMediaSourceDataList
}

struct ExportedMediaSourceDataList: Codable {
    let mediaSources: [ExportedMediaSource]
}

struct ExportedMediaSource: Codable {
    let factoryId: String
    let version: Int
    let arguments: SelectorMediaSourceArguments
}

enum MediaSourceConfigLoaderError: LocalizedError {
    case invalidResponse
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response while downloading media source config."
        case .encodingFailed:
            return "Failed to encode media source config for storage."
        }
    }
}
