import SwiftUI

struct ConversationView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppleTranslator.self) private var translator
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ConversationModel?
    @State private var showInfo = false
    let conversationId: UUID

    var body: some View {
        Group {
            if let model {
                ConversationContent(model: model, showInfo: $showInfo)
            } else {
                ProgressView()
            }
        }
        .background(AmbientBackground())
        .task {
            let model = ConversationModel(conversationId: conversationId, session: session, translator: translator)
            self.model = model
            await model.start()
        }
        .onDisappear { model?.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model?.load() } }
        }
        .sheet(isPresented: $showInfo) {
            if let conversation = model?.conversation, conversation.isGroup {
                GroupInfoView(conversationId: conversation.id) { Task { await model?.load() } }
            }
        }
    }
}

private struct ConversationContent: View {
    @Environment(SessionStore.self) private var session
    @Bindable var model: ConversationModel
    @Binding var showInfo: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.messages) { message in
                        MessageBubble(model: model, message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { Composer(model: model) }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(model.title).font(.headline)
                    if let subtitle = model.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { if model.conversation?.isGroup == true { showInfo = true } }
            }
            if model.conversation?.isGroup == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Groepsinfo", systemImage: "info.circle") { showInfo = true }
                }
            }
        }
        .alert("Let op", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct MessageBubble: View {
    @Environment(SessionStore.self) private var session
    let model: ConversationModel
    let message: Message

    private var isMine: Bool { message.senderId == session.me?.id }
    private var isSpeaking: Bool { model.speakingId == message.id }

    var body: some View {
        HStack(alignment: .bottom) {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                if model.conversation?.isGroup == true, !isMine {
                    Text(session.name(message.senderId))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                if message.isDeleted {
                    Label("Bericht verwijderd", systemImage: "nosign")
                        .font(.callout.italic())
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.displayText(message))
                        .font(.body)
                        .textSelection(.enabled)
                    if model.needsTranslation(message), model.translations[message.id] != nil {
                        Text(message.originalText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    footer
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), tint: isMine ? .accentColor : nil, interactive: true)
            .overlay {
                if isSpeaking {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .contextMenu { menu }
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if message.kind == "voice" {
                Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: isSpeaking)
            }
            if model.failedTranslations.contains(message.id) {
                Image(systemName: "exclamationmark.triangle").help("Vertaling niet beschikbaar")
            }
            Text(message.date, format: .dateTime.hour().minute())
            Text(AppLanguage.named(message.sourceLang))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var menu: some View {
        if !message.isDeleted {
            Button("Voorlezen", systemImage: "speaker.wave.2") { model.speak(message) }
            if message.audioPath != nil {
                Button("Origineel beluisteren", systemImage: "waveform") { Task { await model.playOriginal(message) } }
            }
            Button("Kopieer", systemImage: "doc.on.doc") { UIPasteboard.general.string = model.displayText(message) }
        }
        if model.canDelete(message) {
            Button("Verwijderen", systemImage: "trash", role: .destructive) { Task { await model.delete(message) } }
        }
    }
}

private struct Composer: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(Settings.speechLocaleKey) private var speechLocaleOverride = ""
    @Bindable var model: ConversationModel
    @State private var text = ""
    @State private var pressed = false

    private var locale: String {
        speechLocaleOverride.isEmpty ? (session.me?.speechLocale ?? "nl-BE") : speechLocaleOverride
    }

    var body: some View {
        VStack(spacing: 8) {
            if case .recording(let latched) = model.phase {
                Label(latched ? "Opnemen… tik om te versturen" : "Opnemen… laat los om te versturen", systemImage: "record.circle")
                    .symbolEffect(.pulse)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .glassCapsule()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if model.phase == .processing {
                Label("Verwerken…", systemImage: "ellipsis")
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .glassCapsule()
            }

            HStack(spacing: 10) {
                languageMenu
                TextField("Bericht", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    micButton
                } else {
                    Button {
                        let value = text
                        text = ""
                        Task { await model.sendText(value, locale: locale) }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.title3.weight(.semibold))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(.white)
                    }
                    .glass(in: Circle(), tint: .accentColor, interactive: true)
                    .accessibilityLabel("Verstuur")
                }
            }
            .glassGroup()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth, value: model.phase)
    }

    private var languageMenu: some View {
        Menu {
            Picker("Ik spreek", selection: $speechLocaleOverride) {
                Text("Standaard (\(AppLanguage.named(AppLanguage.code(forLocale: session.me?.speechLocale ?? "nl"))))").tag("")
                ForEach(AppLanguage.all) { language in
                    Text(language.name).tag(language.speechLocale)
                }
            }
        } label: {
            Text(AppLanguage.code(forLocale: locale).uppercased())
                .font(.subheadline.weight(.bold).monospaced())
                .frame(width: 44, height: 44)
        }
        .glass(in: Circle(), interactive: true)
        .accessibilityLabel("Taal waarin je spreekt")
    }

    private var isRecording: Bool {
        if case .recording = model.phase { return true }
        return false
    }

    private var micButton: some View {
        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(isRecording ? .white : .primary)
            .frame(width: 60, height: 60)
            .contentTransition(.symbolEffect(.replace))
            .glass(in: Circle(), tint: isRecording ? .red : nil, interactive: true)
            .scaleEffect(pressed ? 1.12 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        model.pressDown(locale: locale)
                    }
                    .onEnded { _ in
                        pressed = false
                        model.pressUp(locale: locale)
                    }
            )
            .disabled(model.phase == .processing)
            .accessibilityLabel(isRecording ? "Stop opname" : "Neem spraakbericht op")
            .accessibilityAddTraits(.isButton)
    }
}
