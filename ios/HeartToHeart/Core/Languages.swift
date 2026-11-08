import Foundation

/// Languages offered in the app. Apple's on-device Translation framework decides at
/// runtime which pairs are actually available; unsupported pairs surface an error.
struct AppLanguage: Identifiable, Hashable {
    let code: String          // BCP-47 language code used for translation, e.g. "uk"
    let speechLocale: String  // Locale used for speech recognition, e.g. "uk-UA"
    let name: String

    var id: String { code }

    static let all: [AppLanguage] = [
        .init(code: "nl", speechLocale: "nl-BE", name: "Nederlands"),
        .init(code: "en", speechLocale: "en-US", name: "English"),
        .init(code: "uk", speechLocale: "uk-UA", name: "Українська"),
        .init(code: "de", speechLocale: "de-DE", name: "Deutsch"),
        .init(code: "fr", speechLocale: "fr-FR", name: "Français"),
        .init(code: "es", speechLocale: "es-ES", name: "Español"),
        .init(code: "it", speechLocale: "it-IT", name: "Italiano"),
        .init(code: "pl", speechLocale: "pl-PL", name: "Polski"),
        .init(code: "pt", speechLocale: "pt-BR", name: "Português"),
        .init(code: "tr", speechLocale: "tr-TR", name: "Türkçe"),
    ]

    static func named(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }

    /// "nl-BE" -> "nl"
    static func code(forLocale identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier
            ?? String(identifier.prefix(2)).lowercased()
    }
}
