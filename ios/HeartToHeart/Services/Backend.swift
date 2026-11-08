import Foundation
import Supabase

/// Thin, typed wrapper around Supabase. All authorization is enforced server-side
/// (see supabase/migrations); this class only calls tables and RPCs.
@MainActor
final class Backend {
    let client: SupabaseClient

    init(url: URL, key: String) {
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
    }

    var currentUserId: UUID? { client.auth.currentUser?.id }

    // MARK: Auth

    func sendCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: Self.normalize(email), shouldCreateUser: true)
    }

    func verify(email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: Self.normalize(email), token: code, type: .email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: Profiles

    func profiles() async throws -> [Profile] {
        try await client.from("profiles").select().order("display_name").execute().value
    }

    func updateProfile(_ id: UUID, _ update: ProfileUpdate) async throws {
        try await client.from("profiles").update(update).eq("id", value: id.uuidString).execute()
    }

    // MARK: Contacts & blocks

    func contactIds() async throws -> Set<UUID> {
        struct Row: Decodable { let contact_id: UUID }
        let rows: [Row] = try await client.from("contacts").select("contact_id").execute().value
        return Set(rows.map(\.contact_id))
    }

    func addContact(email: String) async throws {
        try await client.rpc("add_contact_by_email", params: ["contact_email": Self.normalize(email)]).execute()
    }

    func removeContact(_ id: UUID) async throws {
        try await client.from("contacts").delete().eq("contact_id", value: id.uuidString).execute()
    }

    func blockedIds() async throws -> Set<UUID> {
        struct Row: Decodable { let blocked_id: UUID }
        let rows: [Row] = try await client.from("blocks").select("blocked_id").execute().value
        return Set(rows.map(\.blocked_id))
    }

    func block(_ me: UUID, _ other: UUID) async throws {
        struct Row: Encodable { let blocker_id: UUID; let blocked_id: UUID }
        try await client.from("blocks").insert(Row(blocker_id: me, blocked_id: other)).execute()
    }

    func unblock(_ other: UUID) async throws {
        try await client.from("blocks").delete().eq("blocked_id", value: other.uuidString).execute()
    }

    // MARK: Conversations

    func conversations() async throws -> [Conversation] {
        try await client.from("conversations")
            .select("id, kind, title, updated_at, conversation_members(user_id, is_admin)")
            .order("updated_at", ascending: false)
            .execute().value
    }

    func conversation(_ id: UUID) async throws -> Conversation {
        try await client.from("conversations")
            .select("id, kind, title, updated_at, conversation_members(user_id, is_admin)")
            .eq("id", value: id.uuidString)
            .single()
            .execute().value
    }

    func startDirect(with other: UUID) async throws -> UUID {
        try await client.rpc("start_direct", params: ["other": other.uuidString]).execute().value
    }

    func createGroup(title: String, members: [UUID]) async throws -> UUID {
        struct Params: Encodable { let group_title: String; let member_ids: [UUID] }
        return try await client.rpc("create_group", params: Params(group_title: title, member_ids: members)).execute().value
    }

    func addMember(_ member: UUID, to conv: UUID) async throws {
        try await client.rpc("add_group_member", params: ["conv": conv.uuidString, "member": member.uuidString]).execute()
    }

    func removeMember(_ member: UUID, from conv: UUID) async throws {
        try await client.rpc("remove_group_member", params: ["conv": conv.uuidString, "member": member.uuidString]).execute()
    }

    func setAdmin(_ member: UUID, in conv: UUID, _ makeAdmin: Bool) async throws {
        struct Params: Encodable { let conv: UUID; let member: UUID; let make_admin: Bool }
        try await client.rpc("set_group_admin", params: Params(conv: conv, member: member, make_admin: makeAdmin)).execute()
    }

    func renameGroup(_ conv: UUID, title: String) async throws {
        try await client.rpc("rename_group", params: ["conv": conv.uuidString, "group_title": title]).execute()
    }

    func deleteConversation(_ conv: UUID) async throws {
        try await client.rpc("delete_conversation", params: ["conv": conv.uuidString]).execute()
    }

    // MARK: Messages

    func messages(in conv: UUID, limit: Int = 200) async throws -> [Message] {
        let rows: [Message] = try await client.from("messages").select()
            .eq("conversation_id", value: conv.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return rows.reversed()
    }

    func latestMessages(for convs: [UUID]) async throws -> [UUID: Message] {
        guard !convs.isEmpty else { return [:] }
        let rows: [Message] = try await client.from("messages").select()
            .in("conversation_id", values: convs.map(\.uuidString))
            .order("created_at", ascending: false)
            .limit(convs.count * 20)
            .execute().value
        var latest: [UUID: Message] = [:]
        for row in rows where latest[row.conversationId] == nil {
            latest[row.conversationId] = row
        }
        return latest
    }

    func send(_ message: NewMessage) async throws {
        try await client.from("messages").insert(message).execute()
    }

    func deleteMessage(_ id: UUID) async throws {
        try await client.rpc("delete_message", params: ["message": id.uuidString]).execute()
    }

    func uploadVoice(conversation: UUID, message: UUID, fileURL: URL) async throws -> String {
        let path = "\(conversation.uuidString.lowercased())/\(message.uuidString.lowercased()).m4a"
        try await client.storage.from("voice")
            .upload(path, fileURL: fileURL, options: FileOptions(contentType: "audio/mp4"))
        return path
    }

    func downloadVoice(path: String) async throws -> Data {
        try await client.storage.from("voice").download(path: path)
    }

    /// Streams inserts and updates on messages visible to this user (RLS applies).
    func messageChanges() -> (RealtimeChannelV2, AsyncStream<AnyAction>) {
        let channel = client.channel("messages-\(UUID().uuidString)")
        let stream = channel.postgresChange(AnyAction.self, schema: "public", table: "messages")
        return (channel, stream)
    }

    func remove(_ channel: RealtimeChannelV2) async {
        await client.removeChannel(channel)
    }

    // MARK: Owner administration

    func invites() async throws -> [Invite] {
        try await client.from("invites").select("email, created_at").order("created_at", ascending: false).execute().value
    }

    func invite(email: String) async throws {
        try await client.from("invites").insert(["email": Self.normalize(email)]).execute()
    }

    func revokeInvite(email: String) async throws {
        try await client.from("invites").delete().eq("email", value: email).execute()
    }

    func setStatus(_ member: UUID, active: Bool) async throws {
        try await client.rpc("set_member_status", params: ["member": member.uuidString, "new_status": active ? "active" : "disabled"]).execute()
    }

    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Message {
    static func decode(_ action: AnyAction) -> Message? {
        switch action {
        case .insert(let insert): return try? insert.decodeRecord(as: Message.self, decoder: JSONDecoder())
        case .update(let update): return try? update.decodeRecord(as: Message.self, decoder: JSONDecoder())
        case .delete: return nil
        }
    }
}
