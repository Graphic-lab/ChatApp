import SwiftUI

struct ContactsView: View {
    @Environment(SessionStore.self) private var session
    @State private var adding = false
    @State private var email = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.contactProfiles) { contact in
                        HStack {
                            ContactRow(profile: contact)
                            Spacer()
                            if session.blocked.contains(contact.id) {
                                Label("Geblokkeerd", systemImage: "hand.raised.fill")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.red)
                            }
                        }
                        .swipeActions {
                            Button("Verwijder", systemImage: "person.badge.minus", role: .destructive) {
                                Task { await session.perform { try await $0.removeContact(contact.id) } }
                            }
                            if !contact.isOwner {
                                if session.blocked.contains(contact.id) {
                                    Button("Deblokkeer", systemImage: "hand.raised.slash") {
                                        Task { await session.perform { try await $0.unblock(contact.id) } }
                                    }
                                    .tint(.green)
                                } else {
                                    Button("Blokkeer", systemImage: "hand.raised") {
                                        guard let me = session.me?.id else { return }
                                        Task { await session.perform { try await $0.block(me, contact.id) } }
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Veeg naar links om te blokkeren of te verwijderen.")
                }
            }
            .overlay {
                if session.contactProfiles.isEmpty {
                    ContentUnavailableView("Nog geen contacten", systemImage: "person.crop.circle.badge.plus",
                                           description: Text("Voeg iemand toe met zijn of haar e-mailadres."))
                }
            }
            .navigationTitle("Contacten")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Voeg toe", systemImage: "plus") { adding = true }
                }
            }
            .refreshable { await session.refresh() }
            .alert("Contact toevoegen", isPresented: $adding) {
                TextField("E-mailadres", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Button("Annuleer", role: .cancel) { email = "" }
                Button("Voeg toe") {
                    let value = email
                    email = ""
                    Task { await session.perform { try await $0.addContact(email: value) } }
                }
            } message: {
                Text("De persoon moet de app al gebruiken.")
            }
        }
    }
}
