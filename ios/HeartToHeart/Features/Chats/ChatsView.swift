import Supabase
import SwiftUI

struct ChatsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var conversations: [Conversation] = []
    @State private var latest: [UUID: Message] = [:]
    @State private var path: [UUID] = []
    @State private var sheet: SheetKind?
    @State private var search = ""
    @State private var channel: RealtimeChannelV2?

    enum SheetKind: String, Identifiable {
        case newChat, newGroup
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { conversation in
                    NavigationLink(value: conversation.id) {
                        ChatRow(conversation: conversation, last: latest[conversation.id])
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        if session.me?.isOwner == true {
                            Button("Verwijder", systemImage: "trash", role: .destructive) {
                                Task {
                                    if await session.perform({ try await $0.deleteConversation(conversation.id) }) { await load() }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .overlay {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "Nog geen gesprekken",
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text("Tik op het potlood om iemand te spreken.")
                    )
                }
            }
            .searchable(text: $search, prompt: "Zoek")
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nieuw gesprek", systemImage: "person") { sheet = .newChat }
                        Button("Nieuwe groep", systemImage: "person.3") { sheet = .newGroup }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Nieuw")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ConversationView(conversationId: id)
            }
            .refreshable { await load() }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .newChat:
                    ContactPicker(title: "Nieuw gesprek") { contact in
                        Task {
                            guard let backend = session.backend else { return }
                            do {
                                let id = try await backend.startDirect(with: contact.id)
                                await load()
                                path.append(id)
                            } catch {
                                session.errorMessage = AppError.message(for: error)
                            }
                        }
                    }
                case .newGroup:
                    NewGroupView { id in
                        Task {
                            await load()
                            path.append(id)
                        }
                    }
                }
            }
        }
        .task {
            await load()
            await listen()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private var filtered: [Conversation] {
        guard !search.isEmpty else { return conversations }
        return conversations.filter { title(for: $0).localizedCaseInsensitiveContains(search) }
    }

    private func title(for conversation: Conversation) -> String {
        if conversation.isGroup { return conversation.title ?? "Groep" }
        let other = conversation.members.first { $0.userId != session.me?.id }
        return other.map { session.name($0.userId) } ?? "Gesprek"
    }

    private func load() async {
        guard let backend = session.backend else { return }
        do {
            conversations = try await backend.conversations()
            latest = try await backend.latestMessages(for: conversations.map(\.id))
        } catch {
            session.errorMessage = AppError.message(for: error)
        }
    }

    private func listen() async {
        guard channel == nil, let backend = session.backend else { return }
        let (channel, stream) = backend.messageChanges()
        self.channel = channel
        try? await channel.subscribeWithError()
        for await _ in stream {
            await load()
        }
    }
}

private struct ChatRow: View {
    @Environment(SessionStore.self) private var session
    let conversation: Conversation
    let last: Message?

    var body: some View {
        HStack(spacing: 12) {
            if conversation.isGroup {
                Image(systemName: "person.3.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.tint))
            } else {
                Avatar(name: title, size: 48)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline).lineLimit(1)
                    if containsOwner {
                        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow)
                            .accessibilityLabel("Eigenaar")
                    }
                    Spacer()
                    if let last {
                        Text(last.date, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        if conversation.isGroup { return conversation.title ?? "Groep" }
        let other = conversation.members.first { $0.userId != session.me?.id }
        return other.map { session.name($0.userId) } ?? "Gesprek"
    }

    private var containsOwner: Bool {
        !conversation.isGroup && conversation.members.contains { $0.userId != session.me?.id && session.profile($0.userId)?.isOwner == true }
    }

    private var preview: String {
        guard let last else { return "Nog geen berichten" }
        if last.isDeleted { return "Bericht verwijderd" }
        let prefix = last.kind == "voice" ? "🎙 " : ""
        return prefix + last.originalText
    }
}

/// Pick one of your contacts.
struct ContactPicker: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let title: String
    var excluded: Set<UUID> = []
    let onPick: (Profile) -> Void

    var body: some View {
        NavigationStack {
            List(session.contactProfiles.filter { !excluded.contains($0.id) && !session.blocked.contains($0.id) }) { contact in
                Button {
                    onPick(contact)
                    dismiss()
                } label: {
                    ContactRow(profile: contact)
                }
                .tint(.primary)
            }
            .overlay {
                if session.contactProfiles.isEmpty {
                    ContentUnavailableView("Geen contacten", systemImage: "person.crop.circle.badge.plus",
                                           description: Text("Voeg eerst contacten toe in het tabblad Contacten."))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
        }
    }
}

struct ContactRow: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: profile.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name).font(.body.weight(.medium))
                    if profile.isOwner {
                        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.yellow)
                            .accessibilityLabel("Eigenaar")
                    }
                }
                Text(AppLanguage.named(profile.language)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
