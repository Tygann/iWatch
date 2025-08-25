// Services/API/ContentAPI.swift
import Foundation

public protocol ContentAPI {
    // Search returns unified SimpleDTOs
    func search(query: String, page: Int) async throws -> [SimpleDTO]

    // Browse shelves
    func trendingMovies(page: Int) async throws -> [SimpleDTO]
    func trendingTV(page: Int) async throws -> [SimpleDTO]

    // Details
    func movieDetails(id: Int) async throws -> MovieDetailsDTO
    func tvDetails(id: Int) async throws -> TVDetailsDTO
    func tvSeason(id: Int, seasonNumber: Int) async throws -> SeasonDetailsDTO
}







//import Foundation
//
////enum MediaKind {
////    case movie
////    case tv
////}
//
//enum MediaType {
//    case movie
//    case show
//}
//
//protocol ContentAPI {
//    func trendingMovies(page: Int) async throws -> [MovieDTO]
//    func trendingTV(page: Int) async throws -> [TVDTO]
//    func search(query: String, page: Int) async throws -> [SearchResultDTO]
//    func movieDetails(id: Int) async throws -> MovieDTO
//    func tvDetails(id: Int) async throws -> TVDetailsDTO
//    func tvSeason(id: Int, season: Int) async throws -> TVSeasonDTO
//    func tvVideos(id: Int) async throws -> TVVideosDTO
//
//}
