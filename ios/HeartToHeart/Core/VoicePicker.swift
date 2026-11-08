import Foundation

/// Minimal description of a system voice, so voice selection can be unit tested.
struct VoiceCandidate: Equatable {
    let identifier: String
    let language: String      // e.g. "nl-BE"
    let isMale: Bool?         // nil when the system does not say
    let quality: Int          // 1 default, 2 enhanced, 3 premium
}

enum VoicePicker {
    /// Best voice for a language: matching gender first, then preferred region, then quality.
    static func pick(
        from voices: [VoiceCandidate],
        language: String,
        preferredLocale: String?,
        gender: VoiceGender
    ) -> VoiceCandidate? {
        let lang = language.lowercased()
        let matching = voices.filter {
            let code = $0.language.lowercased()
            return code == lang || code.hasPrefix(lang + "-")
        }
        let wantMale = gender == .male
        return matching.max { score($0, preferredLocale, wantMale) < score($1, preferredLocale, wantMale) }
    }

    private static func score(_ voice: VoiceCandidate, _ locale: String?, _ wantMale: Bool) -> Int {
        var score = voice.quality
        if voice.isMale == wantMale { score += 100 }
        if let locale, voice.language.caseInsensitiveCompare(locale) == .orderedSame { score += 10 }
        return score
    }
}
