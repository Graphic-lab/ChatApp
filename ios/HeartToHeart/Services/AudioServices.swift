import AVFoundation
import Speech

enum AudioSession {
    /// Record and play through the same session; routes to AirPods/Bluetooth when connected.
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setActive(true)
    }

    static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}

/// Records AAC audio to a temporary .m4a file.
@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() throws {
        try AudioSession.activate()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        startedAt = Date()
    }

    /// Returns the recording and its duration, or nil when it was too short to be useful.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder, let startedAt else { return nil }
        recorder.stop()
        self.recorder = nil
        self.startedAt = nil
        let duration = Date().timeIntervalSince(startedAt)
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return (recorder.url, duration)
    }

    enum RecorderError: Error { case couldNotStart }
}

/// Speech-to-text with Apple's recognizer; on-device when the language supports it.
enum Transcriber {
    static func transcribe(_ url: URL, locale: String) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            throw TranscriberError.unavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    enum TranscriberError: Error { case unavailable }
}

/// Plays original voice clips.
@MainActor
final class ClipPlayer {
    private var player: AVAudioPlayer?

    func play(_ data: Data) throws {
        try AudioSession.activate()
        player = try AVAudioPlayer(data: data)
        player?.play()
    }

    func stop() { player?.stop() }
}
