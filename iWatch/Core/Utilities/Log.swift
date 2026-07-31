import Foundation

enum Log {
    static func info(_ msg: String)  { print("ℹ️ [iWatch] \(msg)") }
    static func warn(_ msg: String)  { print("⚠️ [iWatch] \(msg)") }
    static func error(_ msg: String) { print("🛑 [iWatch] \(msg)") }
}
