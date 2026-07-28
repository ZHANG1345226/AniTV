//
//  PrivateWKUserContentController.swift
//  AniTV
//
//  Created by Feiran Yang on 2026/3/4.
//


import Foundation
import CoreGraphics
import UIKit

// MARK: - 私有 API 协议映射
@objc private protocol PrivateWKUserContentController {
    func addUserScript(_ script: AnyObject)
    func addScriptMessageHandler(_ scriptMessageHandler: AnyObject, name: String)
    @objc optional func removeScriptMessageHandler(forName name: String)
}

@objc private protocol PrivateWKWebViewConfiguration {
    var userContentController: AnyObject { get set }
    var allowsInlineMediaPlayback: Bool { get set }
    // 新增：禁止媒体播放需要用户交互
    var mediaTypesRequiringUserActionForPlayback: Int { get set }
}

private enum MatchResult {
    case continueMatching
    case loadPage(String)
    case matched(url: String, headers: [String: String])
}

// MARK: - 解析器主类
final class TVOSMediaResolver: NSObject {
    static let shared = TVOSMediaResolver()
    
    /// 是否在屏幕上可视化渲染网页（Debug 模式）
    static var isDebugRenderEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "TVOSMediaResolver_isDebugRenderEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "TVOSMediaResolver_isDebugRenderEnabled")
        }
    }
    
    private var webView: AnyObject?
    private var InterceptContentController: AnyObject?
    private var drainingWebViews: [ObjectIdentifier: AnyObject] = [:]
    
    // Debug 模式 UI
    private var debugContainerView: UIView?
    private var debugStatusLabel: UILabel?
    private var debugLogTextView: UITextView?
    private var debugLogLines: [String] = []
    
    // 状态管理
    private var activeContinuation: CheckedContinuation<ExtractionResult, Error>?
    private var handledUrls = Set<String>()
    private var currentConfig: SelectorSearchConfig.MatchVideoConfig?
    private var currentPageUrl: String = ""

    private override init() {
        super.init()
    }
    
    @MainActor
    private func updateDebugStatus(_ status: String) {
        guard Self.isDebugRenderEnabled else { return }
        debugStatusLabel?.text = "🐛 [Debug] " + status
    }
    
    @MainActor
    private func appendDebugLog(_ line: String) {
        print(line)
        guard Self.isDebugRenderEnabled else { return }
        debugLogLines.append(line)
        if debugLogLines.count > 60 { debugLogLines.removeFirst() }
        let fullText = debugLogLines.joined(separator: "\n")
        debugLogTextView?.text = fullText
        let bottomRange = NSRange(location: (fullText as NSString).length, length: 0)
        debugLogTextView?.scrollRangeToVisible(bottomRange)
    }
    
    /// 核心入口方法：输入 URL 和配置，输出 (m3u8, headers, cookies)
    @MainActor
    func resolve(pageUrl: String, config: SelectorSearchConfig.MatchVideoConfig) async throws -> ExtractionResult {
        cancelResolve()
        self.currentConfig = config
        self.currentPageUrl = pageUrl
        self.handledUrls.removeAll()
        self.debugLogLines.removeAll()
        
        initWebViewIfNeeded()
        
        // 1. 强行挂载防休眠 / Debug 可视化挂载
        forceAttachToScreen()
        appendDebugLog("⏳ 开始解析页面: \(pageUrl)")
        appendDebugLog("📋 [Nested正则]: \(config.matchNestedUrl)")
        appendDebugLog("📋 [Video正则]: \(config.matchVideoUrl)")
        
        // 2. 存活探针：测试 JS 引擎是否在工作
        let jsTest = "navigator.userAgent"
        _ = self.webView?.perform(Selector(("evaluateJavaScript:completionHandler:")), with: jsTest, with: { (result: Any?, error: Error?) in
            if let err = error {
                print("❌ JS 引擎测试失败: \(err.localizedDescription)")
            } else {
                print("✅ JS 引擎工作正常，当前 UA: \(String(describing: result))")
            }
        } as @convention(block) (Any?, Error?) -> Void)
        
        // 设置 User-Agent
        _ = webView?.perform(Selector(("setCustomUserAgent:")), with: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3")
        
        return try await withThrowingTaskGroup(of: ExtractionResult.self) { group in
            defer {
                if Self.isDebugRenderEnabled {
                    // Debug 模式下延迟 12 秒销毁，留出更多观察时间
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 12_000_000_000)
                        self?.teardownWebView()
                    }
                } else {
                    teardownWebView()
                }
            }

            // 任务 1：启动 WebView 提取
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        self.activeContinuation = continuation
                        if let url = URL(string: pageUrl) {
                            let request = URLRequest(url: url)
                            print("⏳ 开始加载页面: \(pageUrl)")
                            _ = self.webView?.perform(Selector(("loadRequest:")), with: request)
                        } else {
                            continuation.resume(throwing: URLError(.badURL))
                            self.activeContinuation = nil
                        }
                    }
                } onCancel: {
                    // 当 Task Group 取消这个任务时，触发此闭包
                    Task { @MainActor [weak self] in
                        self?.finishResolve(with: .failure(CancellationError()))
                    }
                }
            }
            
            // 任务 2：15秒超时控制 (对应 KMP 的 DEFAULT_TIMEOUT)
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                await self.updateDebugStatus("⏰ 解析超时 (15s)，保持网页与控制台显示中...")
                await self.appendDebugLog("❌ [TIMEOUT] 15秒解析超时")
                throw NSError(domain: "com.anitv.timeout", code: 408, userInfo: [NSLocalizedDescriptionKey: "解析超时"])
            }
            
            // 获取最先完成的结果（成功或超时）
            let result = try await group.next()!
            group.cancelAll() // 取消另一个任务
            return result
        }
    }

    @MainActor
    func cancelResolve() {
        finishResolve(with: .failure(CancellationError()))
        teardownWebView()
    }
    
    // MARK: - 匹配逻辑 (移植自 KMP matchWebVideo)
    private func matchWebVideo(url: String) -> MatchResult {
        guard let config = currentConfig else { return .continueMatching }
        let range = NSRange(location: 0, length: url.utf16.count)
        
        // 1. 检查是否需要加载嵌套页面 (LoadPage)
        if config.enableNestedUrl, let nestedRegex = config.matchNestedUrlRegex {
            if nestedRegex.firstMatch(in: url, options: [], range: range) != nil {
                return .loadPage(url)
            }
        }
        
        // 2. 检查是否匹配视频链接
        guard let videoRegex = config.matchVideoUrlRegex,
              let match = videoRegex.firstMatch(in: url, options: [], range: range) else {
            return .continueMatching
        }
        
        // 尝试提取命名捕获组 "v"，如果失败则使用整个 url
        var videoUrl = url
        let vRange = match.range(withName: "v")
        if vRange.location != NSNotFound, let swiftRange = Range(vRange, in: url) {
            videoUrl = String(url[swiftRange])
        }
        
        // 构建 KMP 中定义的固定 Header
        let headers = [
            "User-Agent": config.addHeadersToVideo.userAgent,
            "Referer": config.addHeadersToVideo.referer,
            "Sec-Ch-Ua-Mobile": "?0",
            "Sec-Ch-Ua-Platform": "macOS",
            "Sec-Fetch-Dest": "video",
            "Sec-Fetch-Mode": "no-cors",
            "Sec-Fetch-Site": "cross-site"
        ]
        
        return .matched(url: videoUrl, headers: headers)
    }
    
    // MARK: - 提取 URL 内部嵌套的参数 (如 ?url=https://.../index.m3u8)
    private func extractEmbeddedUrls(from urlString: String) -> [String] {
        var results = [String]()
        guard let components = URLComponents(string: urlString),
              let queryItems = components.queryItems else {
            return results
        }
        for item in queryItems {
            if let val = item.value, val.hasPrefix("http://") || val.hasPrefix("https://") {
                results.append(val)
            }
        }
        return results
    }
    
    // MARK: - URL 统一处理中心
    @MainActor
    private func handleInterceptedUrl(_ rawUrl: String) -> Int { // 1 = Allow, 0 = Cancel
        if activeContinuation == nil { return 1 }
        
        // 转换为绝对路径
        let urlObj = URL(string: rawUrl, relativeTo: URL(string: currentPageUrl))
        let url = urlObj?.absoluteString ?? rawUrl
        
        if handledUrls.contains(url) { return 1 }
        handledUrls.insert(url)
        
        // 1. 尝试匹配当前 URL
        let matchResult = matchWebVideo(url: url)
        
        switch matchResult {
        case .loadPage(let nestedUrl):
            updateDebugStatus("🔄 跳转嵌套页面: \(nestedUrl)")
            appendDebugLog("🔄 [嵌套页面]: \(nestedUrl)")
            _ = webView?.perform(Selector(("stopLoading")))
            if let targetUrl = URL(string: nestedUrl) {
                let request = URLRequest(url: targetUrl)
                _ = webView?.perform(Selector(("loadRequest:")), with: request)
            }
            return 0
            
        case .matched(let videoUrl, let headers):
            updateDebugStatus("✅ 提取成功: \(videoUrl)")
            appendDebugLog("✅ [匹配成功直链]: \(videoUrl)")
            
            // 提取 Cookies
            let cookieString = extractCookies(for: currentPageUrl)
            
            let result = ExtractionResult(m3u8Url: videoUrl, headers: headers, cookieString: cookieString)
            finishResolve(with: .success(result))
            return 0
            
        case .continueMatching:
            // 2. 若未匹配，解出 URL 参数中的嵌套直链 (如 mp4.php?url=https://.../index.m3u8)
            let embeddedUrls = extractEmbeddedUrls(from: url)
            for embeddedUrl in embeddedUrls {
                if !handledUrls.contains(embeddedUrl) {
                    handledUrls.insert(embeddedUrl)
                    appendDebugLog("🔍 [解出参数URL尝试匹配]: \(embeddedUrl)")
                    let embeddedMatch = matchWebVideo(url: embeddedUrl)
                    if case .matched(let videoUrl, let headers) = embeddedMatch {
                        updateDebugStatus("✅ 提取成功(来自URL参数): \(videoUrl)")
                        appendDebugLog("✅ [匹配成功直链(来自URL参数)]: \(videoUrl)")
                        let cookieString = extractCookies(for: currentPageUrl)
                        let result = ExtractionResult(m3u8Url: videoUrl, headers: headers, cookieString: cookieString)
                        finishResolve(with: .success(result))
                        return 0
                    }
                }
            }
            appendDebugLog("🔍 [未匹配-非直链/非嵌套]: \(url)")
            return 1
        }
    }
    
    // MARK: - 提取 Cookie
    private func extractCookies(for urlString: String) -> String {
        guard let url = URL(string: urlString),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return ""
        }
        
        // 格式化为 "key1=value1; key2=value2"
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    
    // MARK: - WebView 生命周期管理
    @MainActor
    private func cleanup() {
        _ = webView?.perform(Selector(("stopLoading")))
        _ = webView?.perform(Selector(("loadHTMLString:baseURL:")), with: "", with: nil)
    }

    @MainActor
    private func teardownWebView() {
        if let container = debugContainerView {
            container.removeFromSuperview()
            debugContainerView = nil
            debugStatusLabel = nil
            debugLogTextView = nil
        }
        
        guard let webView else { return }
        let retiringWebView = webView
        self.webView = nil

        _ = retiringWebView.perform(Selector(("stopLoading")))
        _ = retiringWebView.perform(Selector(("setNavigationDelegate:")), with: nil)

        if let config = retiringWebView.value(forKey: "configuration") as? NSObject,
           let contentController = config.value(forKey: "userContentController") as? NSObject {
            let removeHandlerSelector = Selector(("removeScriptMessageHandlerForName:"))
            if contentController.responds(to: removeHandlerSelector) {
                _ = contentController.perform(removeHandlerSelector, with: "AniTVIntercept")
            }

            let removeAllUserScriptsSelector = Selector(("removeAllUserScripts"))
            if contentController.responds(to: removeAllUserScriptsSelector) {
                _ = contentController.perform(removeAllUserScriptsSelector)
            }
        }

        if let view = retiringWebView as? UIView {
            view.removeFromSuperview()
        }

        // Let WebKit finish invalidating its internal background assertion before
        // releasing the last strong reference, otherwise tvOS can abort in
        // RBSAssertion dealloc.
        let drainKey = ObjectIdentifier(retiringWebView)
        drainingWebViews[drainKey] = retiringWebView
        _ = retiringWebView.perform(Selector(("loadHTMLString:baseURL:")), with: "", with: nil)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self else { return }
            _ = self.drainingWebViews[drainKey]?.perform(Selector(("stopLoading")))
            self.drainingWebViews.removeValue(forKey: drainKey)
        }

        self.InterceptContentController = nil
        self.currentConfig = nil
        self.currentPageUrl = ""
        self.handledUrls.removeAll()
    }

    @MainActor
    private func finishResolve(with result: Result<ExtractionResult, Error>) {
        guard let continuation = activeContinuation else { return }
        activeContinuation = nil

        switch result {
        case .success(let extractionResult):
            continuation.resume(returning: extractionResult)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
    
    @MainActor
    private func initWebViewIfNeeded() {
        if self.webView != nil { return }
        
        print("--- 开始初始化 WebView ---")
        
        // 1. 强制加载动态库
        let handle = dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOW)
        if handle == nil {
            print("❌ dlopen 加载 WebKit 失败")
            return
        }
        print("✅ 1. WebKit 动态库加载成功")
        
        // 2. 获取基础类
        guard let webViewClass = NSClassFromString("WKWebView") as? NSObject.Type else {
            print("❌ 找不到 WKWebView 类")
            return
        }
        
        // 3. 使用最基础的无参 init 实例化！完美避开 CGRect 结构体崩溃
        let webViewInstance = webViewClass.init()
        print("✅ 2. WKWebView 实例创建成功")
        
        // 4. 利用 KVC (键值编码) 强行挖出自动生成的配置对象
        guard let config = webViewInstance.value(forKey: "configuration") as? NSObject,
              let contentController = config.value(forKey: "userContentController") as? NSObject else {
            print("❌ 无法获取 configuration 或 userContentController")
            return
        }
        print("✅ 3. 成功提取 configuration 和 userContentController")
        
        // 5. 注入拦截 JS
        guard let userScriptClass = NSClassFromString("WKUserScript") else { return }
        let userScriptType = unsafeBitCast(userScriptClass, to: PrivateWKUserScript.Type.self)
        
        let injectionScript = """
        (function() {
            if (window.__AniTVInterceptInstalled) return;
            window.__AniTVInterceptInstalled = true;

            function postUrl(value) {
                if (!value) return;
                try {
                    const url = typeof value === 'string' ? value : value.url || value.href || String(value);
                    if (!url) return;
                    window.webkit.messageHandlers.AniTVIntercept.postMessage(url);
                } catch (e) {}
            }

            const oldFetch = window.fetch;
            window.fetch = function() {
                postUrl(arguments[0]);
                return oldFetch.apply(this, arguments);
            };

            const oldOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                postUrl(url);
                return oldOpen.apply(this, arguments);
            };

            const originalElementSetAttribute = Element.prototype.setAttribute;
            Element.prototype.setAttribute = function(name, value) {
                if (name === 'src' || name === 'href') {
                    postUrl(value);
                }
                return originalElementSetAttribute.apply(this, arguments);
            };

            function hookSrcProperty(proto) {
                if (!proto) return;
                const descriptor = Object.getOwnPropertyDescriptor(proto, 'src');
                if (!descriptor || !descriptor.set) return;
                Object.defineProperty(proto, 'src', {
                    configurable: true,
                    enumerable: descriptor.enumerable,
                    get: descriptor.get
                        ? function() { return descriptor.get.call(this); }
                        : function() { return this.getAttribute('src'); },
                    set: function(value) {
                        postUrl(value);
                        descriptor.set.call(this, value);
                    }
                });
            }

            hookSrcProperty(typeof HTMLMediaElement !== 'undefined' ? HTMLMediaElement.prototype : null);
            hookSrcProperty(typeof HTMLSourceElement !== 'undefined' ? HTMLSourceElement.prototype : null);
            hookSrcProperty(typeof HTMLIFrameElement !== 'undefined' ? HTMLIFrameElement.prototype : null);
        })();
        """
        
        let userScript = userScriptType.init(source: injectionScript, injectionTime: 0, forMainFrameOnly: false)
        
        let addUserScriptSelector = Selector(("addUserScript:"))
        let addMessageHandlerSelector = Selector(("addScriptMessageHandler:name:"))

        guard contentController.responds(to: addUserScriptSelector) else {
            print("❌ userContentController 不响应 addUserScript:")
            return
        }

        guard contentController.responds(to: addMessageHandlerSelector) else {
            print("❌ userContentController 不响应 addScriptMessageHandler:name:")
            return
        }

        _ = contentController.perform(addUserScriptSelector, with: userScript)
        _ = contentController.perform(addMessageHandlerSelector, with: self, with: "AniTVIntercept")
        print("✅ 4. JS 劫持脚本注入成功")
        
        // 6. 配置属性
        config.setValue(true, forKey: "allowsInlineMediaPlayback")
        
        // 7. 设置网络代理
        _ = webViewInstance.perform(Selector(("setNavigationDelegate:")), with: self)
        print("✅ 5. 代理设置成功，初始化完成！")
        
        self.InterceptContentController = contentController
        self.webView = webViewInstance
    }
    
    @MainActor
    private func forceAttachToScreen() {
        guard let webViewObj = self.webView else {
            print("⚠️ webView 为 nil，无法挂载")
            return
        }
        
        // 绕过 Swift 的运行时安全检查，暴力强转为 UIView
        let view = unsafeDowncast(webViewObj, to: UIView.self)
        
        // 寻找最顶层的 ViewController 强行塞入
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            
            if Self.isDebugRenderEnabled {
                // Debug 模式：全屏渲染 + 顶部调试控制条 + 底部日志控制条
                let container = UIView(frame: rootVC.view.bounds)
                container.backgroundColor = .black
                container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

                let headerHeight: CGFloat = 60
                let logHeight: CGFloat = 180

                let header = UIView(frame: CGRect(x: 0, y: 0, width: container.bounds.width, height: headerHeight))
                header.backgroundColor = UIColor(white: 0.1, alpha: 0.95)
                header.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]

                let statusLabel = UILabel(frame: CGRect(x: 20, y: 10, width: container.bounds.width - 170, height: 40))
                statusLabel.textColor = .white
                statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
                statusLabel.text = "🐛 [Debug] 开始加载页面: \(currentPageUrl)"
                statusLabel.numberOfLines = 2
                statusLabel.adjustsFontSizeToFitWidth = true
                header.addSubview(statusLabel)
                self.debugStatusLabel = statusLabel

                let closeButton = UIButton(type: .system)
                closeButton.frame = CGRect(x: container.bounds.width - 140, y: 10, width: 120, height: 40)
                closeButton.setTitle("关闭 Debug", for: .normal)
                closeButton.setTitleColor(.systemRed, for: .normal)
                closeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
                closeButton.backgroundColor = UIColor(white: 0.25, alpha: 1.0)
                closeButton.layer.cornerRadius = 8
                closeButton.autoresizingMask = [.flexibleLeftMargin]
                closeButton.addTarget(self, action: #selector(handleCloseDebugOverlay), for: .touchUpInside)
                header.addSubview(closeButton)

                let logView = UITextView(frame: CGRect(x: 0, y: container.bounds.height - logHeight, width: container.bounds.width, height: logHeight))
                logView.backgroundColor = UIColor(white: 0.05, alpha: 0.9)
                logView.textColor = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
                logView.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
                logView.isSelectable = false
                logView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
                logView.text = "🔍 --- 拦截日志控制台 ---"
                self.debugLogTextView = logView
                self.debugLogLines = ["🔍 --- 拦截日志控制台 ---"]

                view.frame = CGRect(x: 0, y: headerHeight, width: container.bounds.width, height: container.bounds.height - headerHeight - logHeight)
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.alpha = 1.0
                view.isUserInteractionEnabled = true

                container.addSubview(header)
                container.addSubview(view)
                container.addSubview(logView)

                rootVC.view.addSubview(container)
                rootVC.view.bringSubviewToFront(container)
                self.debugContainerView = container
                print("✅ [Debug 模式] WebView 已挂载并置顶全屏显示！")
            } else {
                view.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
                view.alpha = 0.01
                view.isUserInteractionEnabled = false

                if view.superview == nil {
                    rootVC.view.addSubview(view)
                    rootVC.view.sendSubviewToBack(view)
                    print("✅ WebView 已经强制注射到屏幕视图层级中！")
                }
            }
        } else {
            print("❌ 找不到活跃的屏幕层级，WebView 必定被系统挂起！")
        }
    }

    @objc @MainActor
    private func handleCloseDebugOverlay() {
        teardownWebView()
    }
}

// MARK: - 私有代理回调扩展
extension TVOSMediaResolver {
    
    // 处理 JS 传递过来的 URL (对应 WKScriptMessageHandler)
    @objc(userContentController:didReceiveScriptMessage:)
    func userContentController(_ userContentController: AnyObject, didReceive message: AnyObject) {
        guard let body = message.value(forKey: "body") as? String else { return }
        Task { @MainActor in _ = handleInterceptedUrl(body) }
    }
    
    // 处理导航拦截 (对应 WKNavigationDelegate)
    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: AnyObject, decidePolicyFor action: AnyObject, decisionHandler: @escaping @convention(block) (Int) -> Void) {
        guard let request = action.value(forKey: "request") as? URLRequest,
              let urlStr = request.url?.absoluteString else {
            decisionHandler(1)
            return
        }
        Task { @MainActor in
            let policy = handleInterceptedUrl(urlStr)
            decisionHandler(policy)
        }
    }
    
    // MARK: - WebView 状态探针
    @objc(webView:didCommitNavigation:)
    func webView(_ webView: AnyObject, didCommit navigation: AnyObject?) {
        print("🚀 网页开始接收数据响应...")
        Task { @MainActor in
            updateDebugStatus("🚀 网页开始接收数据响应...")
            appendDebugLog("🚀 [导航] 开始接收数据响应")
        }
    }
    
    @objc(webView:didFinishNavigation:)
    func webView(_ webView: AnyObject, didFinish navigation: AnyObject?) {
        print("🏁 网页加载完毕 (未匹配到 m3u8 时进行 DOM 元素扫描)")
        Task { @MainActor in
            updateDebugStatus("🏁 网页加载完毕，正在进行 DOM 探针扫描...")
            appendDebugLog("🏁 [导航] 网页加载完成，触发 DOM 探针扫描")
        }
        
        let domProbeJS = """
        (function() {
            try {
                const urls = [];
                document.querySelectorAll('video, source, iframe, a').forEach(el => {
                    if (el.src) urls.push(el.src);
                    if (el.href) urls.push(el.href);
                });
                if (window.player_data && window.player_data.url) urls.push(window.player_data.url);
                if (window.cms_player && window.cms_player.url) urls.push(window.cms_player.url);
                if (window.config && window.config.url) urls.push(window.config.url);
                return JSON.stringify(urls);
            } catch(e) { return "[]"; }
        })();
        """
        
        _ = webView.perform(Selector(("evaluateJavaScript:completionHandler:")), with: domProbeJS, with: { (result: Any?, error: Error?) in
            if let jsonStr = result as? String,
               let data = jsonStr.data(using: .utf8),
               let urls = try? JSONSerialization.jsonObject(with: data) as? [String] {
                Task { @MainActor [weak self] in
                    for u in urls {
                        _ = self?.handleInterceptedUrl(u)
                    }
                }
            }
        } as @convention(block) (Any?, Error?) -> Void)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: AnyObject, didFailProvisionalNavigation navigation: AnyObject?, withError error: NSError) {
        print("❌ 网页早期加载失败: \(error.localizedDescription) - 代码: \(error.code)")
        Task { @MainActor in
            updateDebugStatus("❌ 网页早期加载失败: \(error.localizedDescription)")
            appendDebugLog("❌ 网页早期加载失败: \(error.localizedDescription)")
            finishResolve(with: .failure(error))
            cleanup()
        }
    }
    
    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: AnyObject, didFail navigation: AnyObject?, withError error: NSError) {
        print("❌ 网页导航过程失败: \(error.localizedDescription)")
        Task { @MainActor in
            updateDebugStatus("❌ 网页导航失败: \(error.localizedDescription)")
            appendDebugLog("❌ 网页导航失败: \(error.localizedDescription)")
            finishResolve(with: .failure(error))
            cleanup()
        }
    }
}

// MARK: - 私有 API 构造器映射
@objc private protocol PrivateWKUserScript {
    // 明确告诉 Swift 这三个参数的类型，特别是 Int 和 Bool 这类基础类型
    init(source: String, injectionTime: Int, forMainFrameOnly: Bool)
}

@objc private protocol PrivateWKWebView {
    // 明确告诉 Swift 这里接收的是 CGRect 结构体
    init(frame: CGRect, configuration: AnyObject)
}
