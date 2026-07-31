import Foundation

struct AppConfig {
    let tmdbKey: String
    let traktClientId: String
    let traktClientSecret: String
    let traktRedirectURI: String

    static func load() -> AppConfig {
        // 1) Read from Info.plist (build settings or manual entries)
        let info = Bundle.main.infoDictionary ?? [:]
        func readInfo(_ key: String) -> String? {
            (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }

        // 2) Fallback to Secrets.plist at app bundle root
        let secretsDict: [String: Any]? = {
            if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
               let data = try? Data(contentsOf: url),
               let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                return dict
            }
            return nil
        }()
        func readSecret(_ key: String) -> String? {
            (secretsDict?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }

        let tmdbKey = readInfo("TMDB_API_KEY") ?? readSecret("TMDB_API_KEY") ?? ""
        let traktId = readInfo("TRAKT_CLIENT_ID") ?? readSecret("TRAKT_CLIENT_ID") ?? ""
        let traktSecret = readInfo("TRAKT_CLIENT_SECRET") ?? readSecret("TRAKT_CLIENT_SECRET") ?? ""
        let bundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? readInfo("CFBundleIdentifier")
            ?? "com.tyler.iWatch"
        let traktRedirectURI = readInfo("TRAKT_REDIRECT_URI")
            ?? readSecret("TRAKT_REDIRECT_URI")
            ?? "\(bundleIdentifier)://oauth/callback"

        #if DEBUG
        if tmdbKey.isEmpty { print("[AppConfig] WARNING: TMDB_API_KEY is missing.") }
        if traktId.isEmpty { print("[AppConfig] WARNING: TRAKT_CLIENT_ID is missing.") }
        if traktSecret.isEmpty { print("[AppConfig] WARNING: TRAKT_CLIENT_SECRET is missing.") }
        if traktRedirectURI.isEmpty { print("[AppConfig] WARNING: TRAKT_REDIRECT_URI is missing.") }
        #endif

        return AppConfig(
            tmdbKey: tmdbKey,
            traktClientId: traktId,
            traktClientSecret: traktSecret,
            traktRedirectURI: traktRedirectURI
        )
    }
}

private extension String {
    var nonEmpty: String? { self.isEmpty ? nil : self }
}



//struct AppConfig {
//    let tmdbKey: String
//    let traktClientId: String
//    let traktClientSecret: String
//
//    static func load() -> AppConfig {
//        // Try Info.plist first
//        let info = Bundle.main.infoDictionary ?? [:]
//        let tmdbKey = info["TMDB_API_KEY"] as? String
//        let traktId = info["TRAKT_CLIENT_ID"] as? String
//        let traktSecret = info["TRAKT_CLIENT_SECRET"] as? String
//
//        // Fallback to Secrets.plist
//        let secretsPath = Bundle.main.path(forResource: "Secrets", ofType: "plist")
//        let secrets = secretsPath.flatMap { NSDictionary(contentsOfFile: $0) as? [String: Any] }
//
//        return AppConfig(
//            tmdbKey: tmdbKey ?? secrets?["TMDB_API_KEY"] as? String ?? "",
//            traktClientId: traktId ?? secrets?["TRAKT_CLIENT_ID"] as? String ?? "",
//            traktClientSecret: traktSecret ?? secrets?["TRAKT_CLIENT_SECRET"] as? String ?? ""
//        )
//    }
//}





//struct AppConfig {
//    let tmdbKey: String
//    let traktClientId: String
//    let traktClientSecret: String
//
//    init(bundle: Bundle = .main) {
//        func read(_ key: String) -> String {
//            // Read from Info.plist (populated by build settings from xcconfig)
//            (bundle.object(forInfoDictionaryKey: key) as? String).flatMap { !$0.isEmpty ? $0 : nil } ?? ""
//        }
//        self.tmdbKey = read("TMDB_API_KEY")
//        self.traktClientId = read("TRAKT_CLIENT_ID")
//        self.traktClientSecret = read("TRAKT_CLIENT_SECRET")
//    }
//}
