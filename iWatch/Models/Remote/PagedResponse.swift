// Models/Remote/PagedResponse.swift
import Foundation

public struct PagedResponse<T: Decodable>: Decodable {
    public let page: Int
    public let results: [T]
    public let totalPages: Int?
    public let totalResults: Int?
    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages   = "total_pages"
        case totalResults = "total_results"
    }
}
