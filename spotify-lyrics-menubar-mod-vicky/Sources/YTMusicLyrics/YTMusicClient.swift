import Foundation

enum YTMusicClient {
    private static let domain = "https://music.youtube.com"
    private static let baseAPI = domain + "/youtubei/v1/"
    private static let apiParams = "?alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private static let requestTimeout: TimeInterval = 15

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: config)
    }()

    private static let lock = NSLock()
    private static var visitorID: String?
    private static var webClientVersion: String = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return "1." + formatter.string(from: Date()) + ".01.00"
    }()

    static func post(endpoint: String, body: [String: Any], mobile: Bool = false) -> [String: Any]? {
        ensureVisitorID()
        guard let url = URL(string: baseAPI + endpoint + apiParams) else { return nil }

        var payload = body
        payload["context"] = clientContext(mobile: mobile)

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(domain, forHTTPHeaderField: "Origin")
        if let visitorID {
            request.setValue(visitorID, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseObject: [String: Any]?
        let task = session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            responseObject = json
        }
        task.resume()
        if semaphore.wait(timeout: .now() + requestTimeout + 1) == .timedOut {
            task.cancel()
        }
        return responseObject
    }

    private static func clientContext(mobile: Bool) -> [String: Any] {
        if mobile {
            return [
                "client": [
                    "clientName": "ANDROID_MUSIC",
                    "clientVersion": "7.21.50",
                    "hl": "en",
                ],
                "user": [:] as [String: Any],
            ]
        }
        return [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": webClientVersion,
                "hl": "en",
            ],
            "user": [:] as [String: Any],
        ]
    }

    private static func ensureVisitorID() {
        lock.lock()
        defer { lock.unlock() }
        guard visitorID == nil else { return }
        visitorID = fetchVisitorID()
    }

    private static func fetchVisitorID() -> String? {
        guard let url = URL(string: domain) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var html: String?
        let task = session.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data else { return }
            html = String(data: data, encoding: .utf8)
        }
        task.resume()
        if semaphore.wait(timeout: .now() + requestTimeout + 1) == .timedOut {
            task.cancel()
            return nil
        }
        guard let html else { return nil }
        guard let match = html.range(of: #"ytcfg\.set\s*\(\s*\{.+?\}\s*\)\s*;"#, options: .regularExpression) else {
            return nil
        }
        let snippet = String(html[match])
        guard let jsonStart = snippet.firstIndex(of: "{"),
              let jsonEnd = snippet.lastIndex(of: "}") else {
            return nil
        }
        let jsonString = String(snippet[jsonStart...jsonEnd])
        guard let data = jsonString.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return config["VISITOR_DATA"] as? String
    }

    #if DEBUG
    static func resetForTesting() {
        lock.lock()
        visitorID = nil
        lock.unlock()
    }
    #endif
}
