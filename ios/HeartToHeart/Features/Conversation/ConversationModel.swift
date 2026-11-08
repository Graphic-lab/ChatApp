import Foundation
import Observation
import Supabase

/// State and pipeline for one conversation.
/// Send:    record → transcribe (sender's speech locale) → upload clip → insert message
/// Receive: realtime insert → translate to my language (on device) → speak with the sender's voice gender
@MainActor
@Observable
final class ConversationModel {
    enum Phase: Equatable { case idle, recording(latched: Bool), processing }

    let conversationId: UUID
    private let session: SessionStore
    private let translator: AppleTranslator
    private let recorder = VoiceRecorder()
    private let player = ClipPlayer()
    let speaker = Speaker()

    private(set) var conversation: Conversation?
    private(set) var messages: [Message] = []
    private(set) var translations: [UUID: String] = [:]
    private(set) var failedTranslations: Set<UUID> = []
    private(set) var speakingId: UUID?
    var phase: Phase = .idle
    var gesture = RecordingGesture()
    var errorMessage: String?

    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var startedAt = Date()

    init(conversationId: UUID, session: SessionStore, translator: AppleTranslator) {
        self.conversationId = conversationId
        self.session = session
        self.translator = translator
        speaker.onChange = { [weak self] in self?.speakingId = self?.speaker.speakingId }
    }

    var me: Profile? { session.me }

    var title: String {
        guard let conversation else { return "" }
        if conversation.isGroup { return conversation.title ?? "Groep" }
        let other = conversation.members.first { $0.userId != me?.id }
        return other.map { session.name($0.userId) } ?? "Gesprek"
    }

    var subtitle: String? {
        guard let conversation else { return nil }
        if conversation.isGroup { return "\(conversation.members.count) leden" }
        guard let other = conversation.members.first(where: { $0.userId != me?.id }),
              let profile = session.profile(other.userId) else { return nil }
        return "Spreekt \(AppLanguage.named(profile.language))"
    }

    // MARK: Lifecycle

    func start() async {
        startedAt = Date()
        await load()
        subscribe()
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        speaker.stop()
        player.stop()
        if let channel, let backend = session.backend {
            Task { await backend.remove(channel) }
        }
        channel = nil
    }

    func load() async {
        guard let backend = session.backend else { return }
        do {
            async let conv = backend.conversation(conversationId)
            async let rows = backend.messages(in: conversationId)
            conversation = try await conv
            merge(try await rows)
        } catch {
            errorMessage = AppError.message(for: error)
        }
    }

    private func subscribe() {
        guard channel == nil, let backend = session.backend else { return }
        let (channel, stream) = backend.messageChanges()
        self.channel = channel
        listenTask = Task { [weak self] in
            try? await channel.subscribeWithError()
            for await action in stream {
                guard let self, let message = Message.decode(action), message.conversationId == self.conversationId else { continue }
                let isNew = !self.messages.contains { $0.id == message.id }
                self.merge([message])
                if isNew, case .insert = action { self.autoplay(message) }
            }
        }
    }

    private func merge(_ incoming: [Message]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for message in incoming { byId[message.id] = message }
        messages = byId.values.sorted { $0.date < $1.date }
        for message in incoming { Task { await translateIfNeeded(message) } }
    }

    // MARK: Translation & speech

    func needsTranslation(_ message: Message) -> Bool {
        guard let me, !message.isDeleted, message.senderId != me.id else { return false }
        return message.sourceLang != me.language
    }

    private func translateIfNeeded(_ message: Message) async {
        guard needsTranslation(message), let me, translations[message.id] == nil else { return }
        do {
            translations[message.id] = try await translator.translate(message.originalText, from: message.sourceLang, to: me.language)
            failedTranslations.remove(message.id)
        } catch {
            failedTranslations.insert(message.id)
        }
    }

    /// Text the listener should read: translation when needed and available, else the original.
    func displayText(_ message: Message) -> String {
        needsTranslation(message) ? (translations[message.id] ?? message.originalText) : message.originalText
    }

    private func autoplay(_ message: Message) {
        guard UserDefaults.standard.object(forKey: Settings.autoplayKey) as? Bool ?? true,
              message.senderId != me?.id, !message.isDeleted else { return }
        Task {
            await translateIfNeeded(message)
            speak(message)
        }
    }

    func speak(_ message: Message) {
        guard let me else { return }
        let sender = session.profile(message.senderId)
        let language = needsTranslation(message) && translations[message.id] != nil ? me.language : message.sourceLang
        speaker.enqueue(
            id: message.id,
            text: displayText(message),
            language: language,
            preferredLocale: language == me.language ? me.speechLocale : nil,
            gender: sender?.voiceGender ?? .female
        )
    }

    func playOriginal(_ message: Message) async {
        guard let path = message.audioPath, let backend = session.backend else { return }
        do {
            speaker.stop()
            try player.play(try await backend.downloadVoice(path: path))
        } catch {
            errorMessage = "Origineel geluid laden mislukt."
        }
    }

    func stopSpeaking() { speaker.stop() }

    // MARK: Recording

    func pressDown(locale: String) {
        guard let action = gesture.pressDown() else { return }
        handle(action, locale: locale)
    }

    func pressUp(locale: String) {
        if let action = gesture.pressUp() {
            handle(action, locale: locale)
        } else if gesture.state == .latched {
            phase = .recording(latched: true)
        }
    }

    private func handle(_ action: RecordingGesture.Action, locale: String) {
        switch action {
        case .start: Task { await startRecording() }
        case .stop: Task { await finishRecording(locale: locale) }
        }
    }

    private func startRecording() async {
        guard await AudioSession.requestMicrophone() else {
            gesture.reset()
            errorMessage = "Geef toegang tot de microfoon in Instellingen."
            return
        }
        // The press may have ended while the permission prompt was open.
        guard gesture.state != .idle else { return }
        do {
            speaker.stop()
            try recorder.start()
            if case .pressing = gesture.state { phase = .recording(latched: false) } else { phase = .recording(latched: true) }
        } catch {
            gesture.reset()
            phase = .idle
            errorMessage = "Opnemen lukt niet."
        }
    }

    private func finishRecording(locale: String) async {
        guard let clip = recorder.stop() else {
            phase = .idle
            return
        }
        phase = .processing
        defer {
            phase = .idle
            try? FileManager.default.removeItem(at: clip.url)
        }
        guard await AudioSession.requestSpeech() else {
            errorMessage = "Geef toegang tot spraakherkenning in Instellingen."
            return
        }
        do {
            let text = try await Transcriber.transcribe(clip.url, locale: locale).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                errorMessage = "Niets verstaan, probeer opnieuw."
                return
            }
            guard let backend = session.backend else { return }
            let id = UUID()
            let path = try await backend.uploadVoice(conversation: conversationId, message: id, fileURL: clip.url)
            try await send(NewMessage(
                id: id, conversationId: conversationId, kind: "voice",
                originalText: text, sourceLang: AppLanguage.code(forLocale: locale),
                audioPath: path, durationMs: Int(clip.duration * 1000)
            ))
        } catch {
            errorMessage = error is Transcriber.TranscriberError
                ? "Spraakherkenning is niet beschikbaar voor deze taal."
                : AppError.message(for: error)
        }
    }

    func sendText(_ text: String, locale: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await send(NewMessage(
                id: UUID(), conversationId: conversationId, kind: "text",
                originalText: trimmed, sourceLang: AppLanguage.code(forLocale: locale),
                audioPath: nil, durationMs: nil
            ))
        } catch {
            errorMessage = AppError.message(for: error)
        }
    }

    private func send(_ message: NewMessage) async throws {
        guard let backend = session.backend else { return }
        try await backend.send(message)
        await load()
    }

    func delete(_ message: Message) async {
        guard let backend = session.backend else { return }
        do {
            try await backend.deleteMessage(message.id)
            await load()
        } catch {
            errorMessage = AppError.message(for: error)
        }
    }

    func canDelete(_ message: Message) -> Bool {
        guard let me, !message.isDeleted else { return false }
        if me.isOwner { return true }
        return message.senderId == me.id
    }
}

enum Settings {
    static let autoplayKey = "autoplay"
    static let speechLocaleKey = "speechLocaleOverride"
}
