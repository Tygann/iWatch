import Foundation

struct APIRoute {
    var method: String = "GET"
    var baseURL: URL
    var path: String
    var query: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data? = nil

    func urlRequest() -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = body
        return req
    }
}
