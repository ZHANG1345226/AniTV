//
//  LocalHlsPlaybackPreparer.swift
//  AniTV
//
//  Created by Codex on 2026/10/24.
//

import Foundation
import Darwin

/// Lightweight local proxy session serving filtered HLS playlists to AVPlayer on loopback interface (127.0.0.1)
final class LocalHlsProxySession: @unchecked Sendable {
    private var serverSocket: Int32 = -1
    private(set) var port: Int = 0
    private var isClosed = false
    private let lock = NSLock()
    
    private var nextRouteId = 1
    private var remoteRoutes: [String: URL] = [:]
    
    private let headers: [String: String]
    private var initialContent: String = ""
    
    var playlistUrl: URL {
        URL(string: "http://127.0.0.1:\(port)/playlist.m3u8")!
    }
    
    init(masterContent: String, baseUrl: URL, headers: [String: String]) throws {
        self.headers = headers
        try startServer()
        
        self.initialContent = HlsManifestFilter.rewriteMasterPlaylistUris(
            content: masterContent,
            baseUrl: baseUrl
        ) { [unowned self] remoteUrl in
            self.lock.lock()
            defer { self.lock.unlock() }
            let route = "/variant/\(self.nextRouteId).m3u8"
            self.nextRouteId += 1
            self.remoteRoutes[route] = remoteUrl
            return "http://127.0.0.1:\(self.port)\(route)"
        }
    }
    
    init(filteredMediaContent: String) throws {
        self.headers = [:]
        self.initialContent = filteredMediaContent
        try startServer()
    }
    
    private func startServer() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw NSError(domain: "LocalHlsProxy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var opt: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            close(serverSocket)
            throw NSError(domain: "LocalHlsProxy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"])
        }
        
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assignedAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(serverSocket, $0, &addrLen)
            }
        }
        self.port = Int(UInt16(bigEndian: assignedAddr.sin_port))
        
        guard listen(serverSocket, 50) >= 0 else {
            close(serverSocket)
            throw NSError(domain: "LocalHlsProxy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runLoop()
        }
    }
    
    private func runLoop() {
        while true {
            lock.lock()
            let closed = isClosed
            let fd = serverSocket
            lock.unlock()
            if closed || fd < 0 { break }
            
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &clientLen)
                }
            }
            if clientFd < 0 {
                if isClosed { break }
                continue
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientFd: clientFd)
            }
        }
    }
    
    private func handleClient(clientFd: Int32) {
        defer { close(clientFd) }
        
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientFd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }
        
        guard let requestString = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) else { return }
        let requestLine = requestString.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendError(clientFd: clientFd, status: 400)
            return
        }
        
        let path = parts[1]
        if path == "/playlist.m3u8" {
            sendResponse(clientFd: clientFd, content: initialContent)
            return
        }
        
        var targetRemoteUrl: URL?
        lock.lock()
        targetRemoteUrl = remoteRoutes[path]
        lock.unlock()
        
        guard let remoteUrl = targetRemoteUrl else {
            sendError(clientFd: clientFd, status: 404)
            return
        }
        
        var request = URLRequest(url: remoteUrl)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var remoteData: Data?
        var remoteError: Error?
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            remoteData = data
            remoteError = error
            semaphore.signal()
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 10.0)
        
        guard let data = remoteData, remoteError == nil, let rawManifest = String(data: data, encoding: .utf8) else {
            sendError(clientFd: clientFd, status: 502)
            return
        }
        
        let filterResult = HlsManifestFilter.filter(content: rawManifest, baseUrl: remoteUrl.absoluteString)
        let contentToServe: String
        if filterResult.status == .filtered {
            print("🛡️ [LocalHlsProxy] Filtered ad chunks from \(remoteUrl.lastPathComponent) (removed \(filterResult.removedGroups.count) groups)!")
            contentToServe = HlsManifestFilter.rewriteMediaPlaylistUris(content: filterResult.content, baseUrl: remoteUrl)
        } else {
            contentToServe = HlsManifestFilter.rewriteMediaPlaylistUris(content: rawManifest, baseUrl: remoteUrl)
        }
        
        sendResponse(clientFd: clientFd, content: contentToServe)
    }
    
    private func sendResponse(clientFd: Int32, content: String) {
        let bodyBytes = Array(content.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl; charset=utf-8\r\nContent-Length: \(bodyBytes.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        let headerBytes = Array(header.utf8)
        _ = write(clientFd, headerBytes, headerBytes.count)
        _ = write(clientFd, bodyBytes, bodyBytes.count)
    }
    
    private func sendError(clientFd: Int32, status: Int) {
        let msg = "HTTP/1.1 \(status) Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let msgBytes = Array(msg.utf8)
        _ = write(clientFd, msgBytes, msgBytes.count)
    }
    
    func closeServer() {
        lock.lock()
        isClosed = true
        let fd = serverSocket
        serverSocket = -1
        lock.unlock()
        if fd >= 0 {
            close(fd)
        }
    }
    
    deinit {
        closeServer()
    }
}

/// Orchestrates HLS manifest filtering and local proxy sessions for playback.
@MainActor
final class LocalHlsPlaybackPreparer {
    static let shared = LocalHlsPlaybackPreparer()
    
    private static let userDefaultsKey = "isHlsAdFilterEnabled"
    
    /// User preference for enabling HLS patch ad filtering (defaults to true).
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }
    
    private var currentSession: LocalHlsProxySession?
    
    private init() {}
    
    struct PreparedResult {
        let playUrl: URL
        let session: LocalHlsProxySession?
    }
    
    /// Prepares an HLS video stream by downloading the manifest, analyzing for ads,
    /// and starting a local proxy if filtering is needed.
    func prepare(url: String, headers: [String: String]) async -> PreparedResult {
        guard Self.isEnabled else {
            return PreparedResult(playUrl: URL(string: url)!, session: nil)
        }
        
        guard let requestedUrl = URL(string: url),
              let scheme = requestedUrl.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              requestedUrl.pathExtension.lowercased() == "m3u8" || url.contains(".m3u8") else {
            return PreparedResult(playUrl: URL(string: url)!, session: nil)
        }
        
        var request = URLRequest(url: requestedUrl)
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let rawManifest = String(data: data, encoding: .utf8) else {
                return PreparedResult(playUrl: requestedUrl, session: nil)
            }
            
            let baseRemoteUrl = response.url ?? requestedUrl
            let filterResult = HlsManifestFilter.filter(content: rawManifest, baseUrl: baseRemoteUrl.absoluteString)
            
            switch filterResult.status {
            case .filtered:
                print("🛡️ [HlsPlaybackPreparer] Root playlist contains ad chunks! Starting proxy...")
                let rewritten = HlsManifestFilter.rewriteMediaPlaylistUris(content: filterResult.content, baseUrl: baseRemoteUrl)
                let session = try LocalHlsProxySession(filteredMediaContent: rewritten)
                self.currentSession?.closeServer()
                self.currentSession = session
                return PreparedResult(playUrl: session.playlistUrl, session: session)
                
            case .unsupported where filterResult.reason == "master_playlist":
                print("🛡️ [HlsPlaybackPreparer] Root playlist is master playlist! Starting master proxy...")
                let session = try LocalHlsProxySession(masterContent: rawManifest, baseUrl: baseRemoteUrl, headers: headers)
                self.currentSession?.closeServer()
                self.currentSession = session
                return PreparedResult(playUrl: session.playlistUrl, session: session)
                
            case .unchanged, .unsupported:
                print("ℹ️ [HlsPlaybackPreparer] No ad filtering needed (\(filterResult.reason ?? "none")), using direct URL.")
                return PreparedResult(playUrl: requestedUrl, session: nil)
            }
        } catch {
            print("⚠️ [HlsPlaybackPreparer] Failed to prepare HLS stream: \(error). Falling back to direct URL.")
            return PreparedResult(playUrl: requestedUrl, session: nil)
        }
    }
    
    func stopCurrentSession() {
        currentSession?.closeServer()
        currentSession = nil
    }
}
