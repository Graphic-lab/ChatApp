import SwiftUI

struct NewGroupView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selected: Set<UUID> = []
    @State private var busy = false
    let onCreated: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Groepsnaam", text: $title)
                }
                Section("Leden") {
                    ForEach(session.contactProfiles.filter { !session.blocked.contains($0.id) }) { contact in
                        Button {
                            if selected.contains(contact.id) { selected.remove(contact.id) } else { selected.insert(contact.id) }
                        } label: {
                            HStack {
                                ContactRow(profile: contact)
                                Spacer()
                                Image(systemName: selected.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(contact.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    .font(.title3)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Nieuwe groep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Maak") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty || busy)
                }
            }
        }
    }

    private func create() async {
        guard let backend = session.backend else { return }
        busy = true
        defer { busy = false }
        do {
            let id = try await backend.createGroup(title: title, members: Array(selected))
            dismiss()
            onCreated(id)
        } catch {
            session.errorMessage = AppError.message(for: error)
        }
    }
}

struct GroupInfoView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let conversationId: UUID
    let onChange: () -> Void
    @State private var conversation: Conversation?
    @State private var title = ""
    @State private var addingMember = false

    private var me: Profile? { session.me }
    private var amAdmin: Bool {
        me?.isOwner == true || conversation?.members.contains { $0.userId == me?.id && $0.isAdmin } == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Naam") {
                    TextField("Groepsnaam", text: $title)
                        .disabled(!amAdmin)
                        .onSubmit { Task { await run { try await $0.renameGroup(conversationId, title: title) } } }
                }
                Section("\(conversation?.members.count ?? 0) leden") {
                    ForEach(members, id: \.userId) { member in
                        HStack {
                            if let profile = session.profile(member.userId) {
                                ContactRow(profile: profile)
                            }
                            Spacer()
                            if member.isAdmin {
                                Text("Beheerder").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            if canRemove(member) {
                                Button("Verwijder", role: .destructive) {
                                    Task { await run { try await $0.removeMember(member.userId, from: conversationId) } }
                                }
                            }
                            if amAdmin, member.userId != me?.id, session.profile(member.userId)?.isOwner != true {
                                Button(member.isAdmin ? "Geen beheerder" : "Maak beheerder") {
                                    Task { await run { try await $0.setAdmin(member.userId, in: conversationId, !member.isAdmin) } }
                                }
                                .tint(.indigo)
                            }
                        }
                    }
                    if amAdmin {
                        Button("Lid toevoegen", systemImage: "person.badge.plus") { addingMember = true }
                    }
                }
                Section {
                    if me?.isOwner != true {
                        Button("Groep verlaten", role: .destructive) {
                            Task {
                                guard let id = me?.id else { return }
                                if await run({ try await $0.removeMember(id, from: conversationId) }) { dismiss() }
                            }
                        }
                    } else {
                        Button("Groep verwijderen voor iedereen", role: .destructive) {
                            Task { if await run({ try await $0.deleteConversation(conversationId) }) { dismiss() } }
                        }
                    }
                }
            }
            .navigationTitle("Groepsinfo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
            .sheet(isPresented: $addingMember) {
                ContactPicker(title: "Lid toevoegen", excluded: Set(conversation?.members.map(\.userId) ?? [])) { contact in
                    Task { await run { try await $0.addMember(contact.id, to: conversationId) } }
                }
            }
            .task { await load() }
        }
    }

    private var members: [Member] {
        (conversation?.members ?? []).sorted { session.name($0.userId) < session.name($1.userId) }
    }

    /// Mirrors the server rule; the server is the authority.
    private func canRemove(_ member: Member) -> Bool {
        guard amAdmin, member.userId != me?.id else { return false }
        return session.profile(member.userId)?.isOwner != true
    }

    private func load() async {
        guard let backend = session.backend else { return }
        do {
            conversation = try await backend.conversation(conversationId)
            title = conversation?.title ?? ""
        } catch {
            session.errorMessage = AppError.message(for: error)
        }
    }

    @discardableResult
    private func run(_ action: @escaping (Backend) async throws -> Void) async -> Bool {
        let ok = await session.perform(action)
        if ok {
            await load()
            onChange()
        }
        return ok
    }
}
