import Foundation

enum VoiceGender: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Mannenstem" : "Vrouwenstem" }
}

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    var displayName: String
    var language: String
    var speechLocale: String
    var voiceGender: VoiceGender
    let role: String
    var status: String

    var isOwner: Bool { role == "owner" }
    var isActive: Bool { status == "active" }
    var name: String { displayName.isEmpty ? email : displayName }

    enum CodingKeys: String, CodingKey {
        case id, email, language, role, status
        case displayName = "display_name"
        case speechLocale = "speech_locale"
        case voiceGender = "voice_gender"
    }
}

struct ProfileUpdate: Encodable {
    let displayName: String
    let language: String
    let speechLocale: String
    let voiceGender: VoiceGender

    enum CodingKeys: String, CodingKey {
        case language
        case displayName = "display_name"
        case speechLocale = "speech_locale"
        case voiceGender = "voice_gender"
    }
}

struct Member: Codable, Hashable {
    let userId: UUID
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case isAdmin = "is_admin"
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: UUID
    let kind: String
    let title: String?
    let updatedAt: String
    var members: [Member]

    var isGroup: Bool { kind == "group" }

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case updatedAt = "updated_at"
        case members = "conversation_members"
    }
}

struct Message: Codable, Identifiable, Hashable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let kind: String
    let originalText: String
    let sourceLang: String
    let audioPath: String?
    let durationMs: Int?
    let createdAt: String
    let deletedAt: String?

    var isDeleted: Bool { deletedAt != nil }
    var date: Date { Timestamp.parse(createdAt) ?? .distantPast }

    enum CodingKeys: String, CodingKey {
        case id, kind
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case originalText = "original_text"
        case sourceLang = "source_lang"
        case audioPath = "audio_path"
        case durationMs = "duration_ms"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }
}

struct NewMessage: Encodable {
    let id: UUID
    let conversationId: UUID
    let kind: String
    let originalText: String
    let sourceLang: String
    let audioPath: String?
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind
        case conversationId = "conversation_id"
        case originalText = "original_text"
        case sourceLang = "source_lang"
        case audioPath = "audio_path"
        case durationMs = "duration_ms"
    }
}

struct Invite: Codable, Identifiable, Hashable {
    let email: String
    let createdAt: String
    var id: String { email }

    enum CodingKeys: String, CodingKey {
        case email
        case createdAt = "created_at"
    }
}

/// Postgres timestamps arrive with variable fractional precision; parse them leniently.
enum Timestamp {
    static func parse(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        // Postgres may send "2026-11-08 18:00:00.123456+00" in realtime payloads.
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        let padded = normalized.hasSuffix("+00") ? normalized + ":00" : normalized
        return withFraction.date(from: padded) ?? plain.date(from: padded)
    }
}
