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
    
    private var webView: AnyObject?
    private var InterceptContentController: AnyObject?
    
    // 状态管理
    private var activeContinuation: CheckedContinuation<ExtractionResult, Error>?
    private var handledUrls = Set<String>()
    private var currentConfig: SelectorSearchConfig.MatchVideoConfig?
    private var currentPageUrl: String = ""

    private override init() {
        super.init()
    }
    
    /// 核心入口方法：输入 URL 和配置，输出 (m3u8, headers, cookies)
    @MainActor
    func resolve(pageUrl: String, config: SelectorSearchConfig.MatchVideoConfig) async throws -> ExtractionResult {
        cancelResolve()
        self.currentConfig = config
        self.currentPageUrl = pageUrl
        self.handledUrls.removeAll()
        
        initWebViewIfNeeded()
        
        // 1. 强行挂载防休眠
        forceAttachToScreen()
        
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
            defer { cleanup() }

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
        cleanup()
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
    
    // MARK: - URL 统一处理中心
    @MainActor
    private func handleInterceptedUrl(_ rawUrl: String) -> Int { // 1 = Allow, 0 = Cancel
        if activeContinuation == nil { return 1 }
        
        // 转换为绝对路径
        let urlObj = URL(string: rawUrl, relativeTo: URL(string: currentPageUrl))
        let url = urlObj?.absoluteString ?? rawUrl
        
        if handledUrls.contains(url) { return 1 }
        handledUrls.insert(url)
        
        let matchResult = matchWebVideo(url: url)
        
        switch matchResult {
        case .continueMatching:
            return 1
            
        case .loadPage(let nestedUrl):
            print("🔄 发现嵌套页面，跳转至: \(nestedUrl)")
            _ = webView?.perform(Selector(("stopLoading")))
            if let targetUrl = URL(string: nestedUrl) {
                let request = URLRequest(url: targetUrl)
                _ = webView?.perform(Selector(("loadRequest:")), with: request)
            }
            return 0
            
        case .matched(let videoUrl, let headers):
            print("✅ 成功提取视频直链: \(videoUrl)")
            
            // 提取 Cookies
            let cookieString = extractCookies(for: currentPageUrl)
            
            let result = ExtractionResult(m3u8Url: videoUrl, headers: headers, cookieString: cookieString)
            finishResolve(with: .success(result))
            return 0
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
        
        // 现在可以像普通 UIView 一样操作它了
        view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        
        // 寻找最顶层的 ViewController 强行塞入
        if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {
            
            if view.superview == nil {
                rootVC.view.addSubview(view)
                rootVC.view.sendSubviewToBack(view)
                print("✅ WebView 已经强制注射到屏幕视图层级中！")
            }
        } else {
            print("❌ 找不到活跃的屏幕层级，WebView 必定被系统挂起！")
        }
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
    }
    
    @objc(webView:didFinishNavigation:)
    func webView(_ webView: AnyObject, didFinish navigation: AnyObject?) {
        print("🏁 网页加载完毕 (如果没有触发 m3u8，可能是防爬虫验证，或者正则没写对)")
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: AnyObject, didFailProvisionalNavigation navigation: AnyObject?, withError error: NSError) {
        print("❌ 网页早期加载失败: \(error.localizedDescription) - 代码: \(error.code)")
        Task { @MainActor in
            finishResolve(with: .failure(error))
            cleanup()
        }
    }
    
    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: AnyObject, didFail navigation: AnyObject?, withError error: NSError) {
        print("❌ 网页导航过程失败: \(error.localizedDescription)")
        Task { @MainActor in
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
