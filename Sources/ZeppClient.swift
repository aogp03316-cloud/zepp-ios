import Foundation

enum ZeppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

final class ZeppClient {
    static let shared = ZeppClient()

    private let session: URLSession
    private let deviceId = "2C8B4939-0CCD-4E94-8CBA-CB8EA6E613A1"
    private let bandDeviceId = "DA932FFFFE8816E7"
    private let appUA = "MiFit6.14.0 (M2007J1SC; Android 12; Density/2.75)"
    private let appVersion = "6.14.0"
    private let dnList = "account.zepp.com,api-user.zepp.com,api-mifit.zepp.com,api-watch.zepp.com,app-analytics.zepp.com,api-analytics.huami.com,auth.zepp.com"

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    // MARK: - 工具
    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw ZeppError.message("响应异常")
            }
            return (data, http)
        } catch let e as URLError {
            let hint: String
            switch e.code {
            case .notConnectedToInternet: hint = "手机没联网"
            case .timedOut: hint = "请求超时"
            case .cannotFindHost, .cannotConnectToHost: hint = "连不上服务器（换网络再试）"
            case .networkConnectionLost: hint = "连接被中断"
            case .secureConnectionFailed, .serverCertificateUntrusted: hint = "TLS 证书问题"
            default: hint = e.localizedDescription
            }
            throw ZeppError.message("网络错误(\(e.code.rawValue))：\(hint)")
        }
    }

    // MARK: - 一、登录（新接口 + AES 加密）→ 拿 access code
    private func fetchAccessCode(account: String, password: String) async throws -> String {
        let pairs: [(String, String)] = [
            ("emailOrPhone", account),
            ("password", password),
            ("state", "REDIRECTION"),
            ("client_id", "HuaMi"),
            ("country_code", "CN"),
            ("token", "access"),
            ("redirect_uri", "https://s3-us-west-2.amazonaws.com/hm-registration/successsignin.html")
        ]
        let query = pairs.map { "\($0.0)=\(urlEncode($0.1))" }.joined(separator: "&")
        guard let cipher = AESCrypto.encryptCBC(Data(query.utf8)) else {
            throw ZeppError.message("加密失败")
        }
        guard let url = URL(string: "https://api-user.zepp.com/v2/registrations/tokens") else {
            throw ZeppError.message("URL 错误")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(appUA, forHTTPHeaderField: "User-Agent")
        req.setValue("com.xiaomi.hm.health", forHTTPHeaderField: "app_name")
        req.setValue("com.xiaomi.hm.health", forHTTPHeaderField: "appname")
        req.setValue("android_phone", forHTTPHeaderField: "appplatform")
        req.setValue("1", forHTTPHeaderField: "x-hm-ekv")
        req.setValue("false", forHTTPHeaderField: "hm-privacy-ceip")
        req.httpBody = cipher

        let (data, http) = try await send(req)
        let finalURL = http.url?.absoluteString ?? ""
        let body = String(data: data, encoding: .utf8) ?? ""

        if let r = finalURL.range(of: "access=") {
            let code = String(finalURL[r.upperBound...]).components(separatedBy: "&").first ?? ""
            if !code.isEmpty { return code }
        }
        if finalURL.contains("error=401") {
            throw ZeppError.message("账号或密码错误（华米 401）。邮箱账号请确认用的是注册邮箱")
        }
        if let r = finalURL.range(of: "error=") {
            let e = String(finalURL[r.upperBound...]).components(separatedBy: "&").first ?? ""
            throw ZeppError.message("华米拒绝登录（error=\(e)）")
        }
        if http.statusCode == 429 {
            throw ZeppError.message("请求太频繁（429）。停 20 分钟再试")
        }
        throw ZeppError.message("登录失败 HTTP \(http.statusCode)：\(body.prefix(140))")
    }

    // MARK: - 二、换令牌（邮箱 / 手机号走不同分支）
    private func exchange(code: String, isEmail: Bool) async throws -> (loginToken: String, appToken: String?) {
        guard let url = URL(string: "https://account.huami.com/v2/client/login") else {
            throw ZeppError.message("URL 错误")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(appUA, forHTTPHeaderField: "User-Agent")
        req.setValue("com.xiaomi.hm.health", forHTTPHeaderField: "app_name")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "x-request-id")
        req.setValue("zh-CN", forHTTPHeaderField: "accept-language")
        req.setValue("com.xiaomi.hm.health", forHTTPHeaderField: "appname")
        req.setValue("50818_\(appVersion)", forHTTPHeaderField: "cv")
        req.setValue("2.0", forHTTPHeaderField: "v")
        req.setValue("android_phone", forHTTPHeaderField: "appplatform")

        let body: String
        if isEmail {
            let dn = urlEncode(dnList)
            let source = urlEncode("com.xiaomi.hm.health:\(appVersion):50818")
            body = "allow_registration%3D=false"
                + "&app_name=com.xiaomi.hm.health"
                + "&app_version=\(appVersion)"
                + "&code=\(code)"
                + "&country_code=CN"
                + "&device_id=\(deviceId)"
                + "&device_model=android_phone"
                + "&dn=\(dn)"
                + "&grant_type=access_token"
                + "&lang=zh_CN"
                + "&os_version=1.5.0"
                + "&source=\(source)"
                + "&third_name=email"
        } else {
            body = "app_name=com.xiaomi.hm.health"
                + "&app_version=\(appVersion)"
                + "&code=\(code)"
                + "&country_code=CN"
                + "&device_id=\(deviceId)"
                + "&device_model=phone"
                + "&grant_type=access_token"
                + "&third_name=huami_phone"
        }
        req.httpBody = body.data(using: .utf8)

        let (data, http) = try await send(req)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZeppError.message("换令牌失败 HTTP \(http.statusCode)：\(text.prefix(160))")
        }
        if let result = json["result"] as? String, result != "ok" {
            throw ZeppError.message("换令牌被拒：result=\(result)")
        }
        guard let info = json["token_info"] as? [String: Any],
              let token = info["login_token"] as? String else {
            throw ZeppError.message("换令牌失败：\(text.prefix(160))")
        }
        return (token, info["app_token"] as? String)
    }

    // MARK: - 三、app_token（备用：换令牌没给才调）
    func getAppToken(loginToken: String) async throws -> String {
        var comps = URLComponents(string: "https://account-cn.huami.com/v1/client/app_tokens")!
        comps.queryItems = [
            .init(name: "app_name", value: "com.xiaomi.hm.health"),
            .init(name: "dn", value: "api-user.huami.com,api-mifit.huami.com,app-analytics.huami.com"),
            .init(name: "login_token", value: loginToken)
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("MiFit/5.3.0 (iPhone; iOS 14.7.1; Scale/3.00)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await send(req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["token_info"] as? [String: Any],
              let token = info["app_token"] as? String else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ZeppError.message("取 app_token 失败：\(text.prefix(140))")
        }
        return token
    }

    // MARK: - 四、提交步数
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
        let rid = UUID().uuidString
        guard let url = URL(string: "https://api-mifit-cn.huami.com/v1/data/band_data.json?&t=\(ts)&r=\(rid)") else {
            throw ZeppError.message("URL 错误")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(appToken, forHTTPHeaderField: "apptoken")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "userid=\(loginToken)&last_sync_data_time=1597306380&device_type=0&last_deviceid=\(bandDeviceId)&data_json=\(tpl)"
        req.httpBody = body.data(using: .utf8)

        let (data, http) = try await send(req)
        let text = String(data: data, encoding: .utf8) ?? ""
        if http.statusCode != 200 {
            throw ZeppError.message("提交步数异常 HTTP \(http.statusCode)：\(text.prefix(120))")
        }
        return text
    }

    // MARK: - 一次完整流程
    func push(account: String, password: String, steps: Int) async throws -> String {
        let acc = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = try await fetchAccessCode(account: acc, password: password)
        let (loginToken, appTokenOpt) = try await exchange(code: code, isEmail: acc.contains("@"))
        let appToken = try appTokenOpt ?? await getAppToken(loginToken: loginToken)
        return try await updateSteps(loginToken: loginToken, appToken: appToken, steps: steps)
    }

    static func todayCN() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: Date())
    }
}
