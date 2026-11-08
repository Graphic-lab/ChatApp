import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(Settings.autoplayKey) private var autoplay = true
    @State private var name = ""
    @State private var language = "nl"
    @State private var speechLocale = "nl-BE"
    @State private var voice: VoiceGender = .male
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                if let me = session.me {
                    Section {
                        HStack(spacing: 14) {
                            Avatar(name: me.name, size: 56)
                            VStack(alignment: .leading) {
                                Text(me.name).font(.title3.weight(.semibold))
                                Text(me.email).font(.footnote).foregroundStyle(.secondary)
                            }
                            if me.isOwner {
                                Spacer()
                                Label("Eigenaar", systemImage: "crown.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .glassCapsule(tint: .yellow)
                            }
                        }
                    }
                }

                Section("Profiel") {
                    TextField("Naam", text: $name)
                }

                Section {
                    Picker("Ik lees en hoor", selection: $language) {
                        ForEach(AppLanguage.all) { Text($0.name).tag($0.code) }
                    }
                    Picker("Ik spreek meestal", selection: $speechLocale) {
                        ForEach(AppLanguage.all) { Text($0.name).tag($0.speechLocale) }
                    }
                    Picker("Mijn stem bij de ander", selection: $voice) {
                        ForEach(VoiceGender.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Taal en stem")
                } footer: {
                    Text("Berichten van anderen worden op dit toestel vertaald naar jouw taal. Apple vraagt de eerste keer om de taal te downloaden.")
                }

                Section {
                    Toggle("Automatisch voorlezen", isOn: $autoplay)
                    LabeledContent("Vertaling", value: "Apple, op dit toestel")
                } footer: {
                    Text("Een cloudvertaling met natuurlijkere stemmen kan later als optie toegevoegd worden.")
                }

                if session.me?.isOwner == true {
                    Section("Eigenaar") {
                        NavigationLink("Uitnodigingen en leden") { AdminView() }
                    }
                }

                Section {
                    Button("Uitloggen", role: .destructive) { Task { await session.signOut() } }
                }
            }
            .navigationTitle("Instellingen")
            .onAppear(perform: fill)
            .onChange(of: name) { save() }
            .onChange(of: language) { save() }
            .onChange(of: speechLocale) { save() }
            .onChange(of: voice) { save() }
        }
    }

    private func fill() {
        guard let me = session.me else { return }
        name = me.displayName
        language = me.language
        speechLocale = me.speechLocale
        voice = me.voiceGender
        loaded = true
    }

    private func save() {
        guard loaded, let id = session.me?.id else { return }
        let update = ProfileUpdate(displayName: name.trimmingCharacters(in: .whitespaces), language: language, speechLocale: speechLocale, voiceGender: voice)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard update.displayName == name.trimmingCharacters(in: .whitespaces) else { return }
            await session.perform { try await $0.updateProfile(id, update) }
        }
    }
}
