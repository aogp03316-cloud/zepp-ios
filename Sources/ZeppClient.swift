import Foundation

enum ZeppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

/// 拦截 302，拿到华米登录的 Location（里面有 access=CODE 或 error=401）
final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var _location: String?
    var location: String? {
        get { lock.lock(); defer { lock.unlock() }; return _location }
        set { lock.lock(); _location = newValue; lock.unlock() }
    }
    func reset() { location = nil }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        location = request.url?.absoluteString
        completionHandler(nil)   // 不跟随重定向
    }
}

final class ZeppClient {
    static let shared = ZeppClient()

    private let catcher = RedirectCatcher()
    private let session: URLSession
    private let deviceId = "2C8B4939-0CCD-4E94-8CBA-CB8EA6E613A1"
    private let bandDeviceId = "DA932FFFFE8816E7"

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        ]
        session = URLSession(configuration: cfg, delegate: catcher, delegateQueue: nil)
    }

    // MARK: - 一、登录拿 access code -> login_token
    func login(account: String, password: String) async throws -> String {
        var acc = account.trimmingCharacters(in: .whitespaces)
        if !acc.hasPrefix("+") && !acc.contains("@") { acc = "+86" + acc }
        guard let url = URL(string: "https://api-user.huami.com/registrations/\(acc)/tokens") else {
            throw ZeppError.message("URL 构造失败")
        }
        catcher.reset()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let pwd = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? password
        let body = "client_id=HuaMi&password=\(pwd)&redirect_uri=https%3A%2F%2Fs3-us-west-2.amazonaws.com%2Fhm-registration%2Fsuccesssignin.html&token=access"
        req.httpBody = body.data(using: .utf8)

        _ = try await session.data(for: req)

        guard let loc = catcher.location else {
            throw ZeppError.message("登录无响应（网络被拦？）")
        }
        if let r = loc.range(of: "access=") {
            let code = String(loc[r.upperBound...]).components(separatedBy: "&").first ?? ""
            if code.isEmpty { throw ZeppError.message("没拿到 access code") }
            return try await exchangeToken(code: code)
        }
        if loc.contains("error=401") {
            throw ZeppError.message("账号或密码错误（华米 error=401）")
        }
        if let r = loc.range(of: "error=") {
            let e = String(loc[r.upperBound...]).components(separatedBy: "&").first ?? ""
            throw ZeppError.message("华米拒绝登录（error=\(e)）")
        }
        throw ZeppError.message("登录失败：\(loc)")
    }

    private func exchangeToken(code: String) async throws -> String {
        guard let url = URL(string: "https://account.huami.com/v2/client/login") else {
            throw ZeppError.message("URL 错误")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let body = "app_name=com.xiaomi.hm.health&app_version=6.3.0&code=\(code)&country_code=CN&device_id=\(deviceId)&device_model=phone&grant_type=access_token&third_name=huami_phone"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["token_info"] as? [String: Any],
              let token = info["login_token"] as? String else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ZeppError.message("换取 login_token 失败：\(text.prefix(160))")
        }
        return token
    }

    // MARK: - 二、拿 app_token
    func getAppToken(loginToken: String) async throws -> String {
        var comps = URLComponents(string: "https://account-cn.huami.com/v1/client/app_tokens")!
        comps.queryItems = [
            .init(name: "app_name", value: "com.xiaomi.hm.health"),
            .init(name: "dn", value: "api-user.huami.com,api-mifit.huami.com,app-analytics.huami.com"),
            .init(name: "login_token", value: loginToken),
            .init(name: "os_version", value: "4.1.0")
        ]
        let (data, _) = try await session.data(from: comps.url!)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["token_info"] as? [String: Any],
              let token = info["app_token"] as? String else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ZeppError.message("获取 app_token 失败：\(text.prefix(160))")
        }
        return token
    }

    // MARK: - 三、提交步数
    func updateSteps(loginToken: String, appToken: String, steps: Int) async throws -> String {
        let date = Self.todayCN()
        var tpl = BAND_DATA_TEMPLATE
        tpl = tpl.replacingOccurrences(of: "(ttl%5C%22%3A)\\d+",
                                       with: "$1\(steps)",
                                       options: .regularExpression)
        tpl = tpl.replacingOccurrences(of: "(date%22%3A%22)[\\d-]+",
                                       with: "$1\(date)",
                                       options: .regularExpression)

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "https://api-mifit-cn2.huami.com/v1/data/band_data.json?t=\(ts)") else {
            throw ZeppError.message("URL 错误")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(appToken, forHTTPHeaderField: "apptoken")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "userid=\(loginToken)&last_sync_data_time=\(ts)&device_type=0&last_deviceid=\(bandDeviceId)&data_json=\(tpl)"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: req)
        return String(data: data, encoding: .utf8) ?? "(无返回)"
    }

    // MARK: - 一次完整流程
    func push(account: String, password: String, steps: Int) async throws -> String {
        let loginToken = try await login(account: account, password: password)
        let appToken = try await getAppToken(loginToken: loginToken)
        return try await updateSteps(loginToken: loginToken, appToken: appToken, steps: steps)
    }

    static func todayCN() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: Date())
    }
}
