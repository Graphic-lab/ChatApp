import Foundation

/// Values injected at build time from Config/Secrets.xcconfig via Info.plist.
enum AppConfig {
    static var supabaseURL: URL? {
        guard let raw = value("SUPABASE_URL"), raw.hasPrefix("https://") else { return nil }
        return URL(string: raw)
    }

    static var supabaseKey: String? { value("SUPABASE_ANON_KEY") }

    static var isConfigured: Bool { supabaseURL != nil && supabaseKey != nil }

    private static func value(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("$(") || trimmed.contains("YOUR-") ? nil : trimmed
    }
}
