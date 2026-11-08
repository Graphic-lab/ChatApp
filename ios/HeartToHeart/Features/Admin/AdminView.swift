import SwiftUI

/// Owner-only screen. The server rejects these actions for anyone else.
struct AdminView: View {
    @Environment(SessionStore.self) private var session
    @State private var invites: [Invite] = []
    @State private var email = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("E-mailadres", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Nodig uit") {
                        let value = email
                        email = ""
                        Task {
                            await session.perform { try await $0.invite(email: value) }
                            await load()
                        }
                    }
                    .disabled(!email.contains("@"))
                }
                ForEach(invites) { invite in
                    Text(invite.email)
                        .swipeActions {
                            Button("Intrekken", role: .destructive) {
                                Task {
                                    await session.perform { try await $0.revokeInvite(email: invite.email) }
                                    await load()
                                }
                            }
                        }
                }
            } header: {
                Text("Uitnodigingen")
            } footer: {
                Text("Alleen uitgenodigde e-mailadressen kunnen een account maken.")
            }

            Section("Leden") {
                ForEach(members) { profile in
                    HStack {
                        ContactRow(profile: profile)
                        Spacer()
                        if profile.isOwner {
                            Text("Eigenaar").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Toggle("Actief", isOn: Binding(
                                get: { profile.isActive },
                                set: { active in Task { await session.perform { try await $0.setStatus(profile.id, active: active) } } }
                            ))
                            .labelsHidden()
                        }
                    }
                }
            }
        }
        .navigationTitle("Beheer")
        .task { await load() }
        .refreshable { await load() }
    }

    private var members: [Profile] {
        session.profiles.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func load() async {
        guard let backend = session.backend else { return }
        do {
            invites = try await backend.invites()
        } catch {
            session.errorMessage = AppError.message(for: error)
        }
    }
}
