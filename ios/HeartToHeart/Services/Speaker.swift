import AVFoundation

/// Speaks translated text in order, one utterance at a time.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var speakingId: UUID?
    private var queue: [(id: UUID, utterance: AVSpeechUtterance)] = []
    var onChange: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func enqueue(id: UUID, text: String, language: String, preferredLocale: String?, gender: VoiceGender) {
        guard !text.isEmpty, speakingId != id, !queue.contains(where: { $0.id == id }) else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(language: language, preferredLocale: preferredLocale, gender: gender)
        queue.append((id, utterance))
        pump()
    }

    func stop() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        speakingId = nil
        onChange?()
    }

    private func pump() {
        guard speakingId == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        try? AudioSession.activate()
        speakingId = next.id
        synthesizer.speak(next.utterance)
        onChange?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        speakingId = nil
        onChange?()
        pump()
    }

    static func voice(language: String, preferredLocale: String?, gender: VoiceGender) -> AVSpeechSynthesisVoice? {
        let system = AVSpeechSynthesisVoice.speechVoices()
        let candidates = system.map {
            VoiceCandidate(
                identifier: $0.identifier,
                language: $0.language,
                isMale: $0.gender == .unspecified ? nil : $0.gender == .male,
                quality: $0.quality.rawValue
            )
        }
        guard let best = VoicePicker.pick(from: candidates, language: language, preferredLocale: preferredLocale, gender: gender) else {
            return AVSpeechSynthesisVoice(language: language)
        }
        return AVSpeechSynthesisVoice(identifier: best.identifier)
    }
}
