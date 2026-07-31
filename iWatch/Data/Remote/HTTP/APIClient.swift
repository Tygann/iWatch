import Foundation

final class APIClient {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    // Rename later if you like; keeping your name/signature.
    static func makeDefault(cacheService: CacheService) -> APIClient {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = cacheService.urlCache
        let session = URLSession(configuration: config)
        return APIClient(session: session)
    }

    // MARK: - JSON
    func fetch<T: Decodable>(_ route: APIRoute, as type: T.Type) async throws -> T {
        let (data, resp) = try await session.data(for: route.urlRequest())
        guard let http = resp as? HTTPURLResponse else { throw AppError.network("No response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw AppError.rateLimited(retryAfter: Self.retryAfter(from: http))
            }
            throw AppError.httpStatus(code: http.statusCode,
                                      message: String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder.tmdb.decode(T.self, from: data)
        } catch {
            // DEBUG: surface the real DecodingError details so you don't get a vague "data missing".
            #if DEBUG
            debugPrintDecodeError(error, data: data, route: route, type: T.self)
            #endif
            throw AppError.decoding(error)
        }
    }

    // MARK: - Raw Data
    func data(_ route: APIRoute) async throws -> Data {
        let (data, resp) = try await session.data(for: route.urlRequest())
        guard let http = resp as? HTTPURLResponse else { throw AppError.network("No response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw AppError.rateLimited(retryAfter: Self.retryAfter(from: http))
            }
            throw AppError.httpStatus(code: http.statusCode,
                                      message: String(data: data, encoding: .utf8))
        }
        return data
    }

    // MARK: - URLRequest helper (Trakt + others)
    nonisolated func send<T: Decodable>(
        _ request: URLRequest,
        decode: T.Type,
        decoder: JSONDecoder? = nil
    ) async throws -> T {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw AppError.network("No response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw AppError.rateLimited(retryAfter: Self.retryAfter(from: http))
            }
            throw AppError.httpStatus(code: http.statusCode,
                                      message: String(data: data, encoding: .utf8))
        }
        let dec: JSONDecoder
        if let decoder = decoder {
            dec = decoder
        } else {
            // Local Trakt-style decoder
            let d = JSONDecoder()
            d.keyDecodingStrategy = .convertFromSnakeCase
            d.dateDecodingStrategy = .custom { decoder in
                let c = try decoder.singleValueContainer()
                let s = try c.decode(String.self)
                // Create formatters inside the closure to avoid capturing non-Sendable state
                let f1 = ISO8601DateFormatter()
                f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = f1.date(from: s) { return date }
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                if let date = f2.date(from: s) { return date }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
            }
            dec = d
        }
        return try dec.decode(T.self, from: data)
    }
}

private extension APIClient {
    nonisolated static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }
}

// MARK: - JSONDecoder preset for TMDB
extension JSONDecoder {
    static var tmdb: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Dates are endpoint-specific in this app; set per-call when needed.
        return decoder
    }
}

#if DEBUG
private func debugPrintDecodeError<T>(_ error: Error, data: Data, route: APIRoute, type: T.Type) {
    let urlString = route.urlRequest().url?.absoluteString ?? "<unknown>"

    func printJSONSnippet(_ data: Data) {
        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.count > 600 ? raw.prefix(600) + "…\n(truncated)" : raw[...]
            print("↳ Response snippet:\n\(trimmed)")
        }
    }

    switch error {
    case let DecodingError.keyNotFound(key, ctx):
        print("🧩 Decoding keyNotFound '\(key.stringValue)' in \(type): \(ctx.debugDescription)")
        if !ctx.codingPath.isEmpty { print("↳ CodingPath:", ctx.codingPath.map(\.stringValue).joined(separator: " → ")) }
        print("↳ URL:", urlString)
        printJSONSnippet(data)
    case let DecodingError.typeMismatch(expected, ctx):
        print("🧩 Decoding typeMismatch \(expected) in \(type): \(ctx.debugDescription)")
        if !ctx.codingPath.isEmpty { print("↳ CodingPath:", ctx.codingPath.map(\.stringValue).joined(separator: " → ")) }
        print("↳ URL:", urlString)
        printJSONSnippet(data)
    case let DecodingError.valueNotFound(expected, ctx):
        print("🧩 Decoding valueNotFound \(expected) in \(type): \(ctx.debugDescription)")
        if !ctx.codingPath.isEmpty { print("↳ CodingPath:", ctx.codingPath.map(\.stringValue).joined(separator: " → ")) }
        print("↳ URL:", urlString)
        printJSONSnippet(data)
    case let DecodingError.dataCorrupted(ctx):
        print("🧩 Decoding dataCorrupted in \(type): \(ctx.debugDescription)")
        print("↳ URL:", urlString)
        printJSONSnippet(data)
    default:
        print("🧩 Decoding error in \(type):", error.localizedDescription)
        print("↳ URL:", urlString)
        printJSONSnippet(data)
    }
}
#endif
