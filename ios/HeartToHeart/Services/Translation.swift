import Foundation
import Observation
import SwiftUI
import Translation

/// Translation engine seam. Apple on-device is the default; a cloud engine can be
/// added later behind the same protocol (see specs/design.md, "Cloud option").
@MainActor
protocol MessageTranslator: AnyObject {
    func translate(_ text: String, from source: String, to target: String) async throws -> String
}

/// Apple's Translation framework on iOS 18 only hands out a TranslationSession through
/// the SwiftUI `.translationTask` modifier. This coordinator queues requests and drives
/// that modifier; `TranslationHost` attaches it once at the root of the app.
@MainActor
@Observable
final class AppleTranslator: MessageTranslator {
    private struct Job {
        let id = UUID()
        let text: String
        let source: String
        let target: String
        let continuation: CheckedContinuation<String, Error>
    }

    private var jobs: [Job] = []
    private var running = false
    private var cache: [String: String] = [:]
    var configuration: TranslationSession.Configuration?

    func cached(_ text: String, from source: String, to target: String) -> String? {
        source == target ? text : cache[Self.key(text, source, target)]
    }

    func translate(_ text: String, from source: String, to target: String) async throws -> String {
        if let hit = cached(text, from: source, to: target) { return hit }
        let result = try await withCheckedThrowingContinuation { continuation in
            jobs.append(Job(text: text, source: source, target: target, continuation: continuation))
            scheduleNext()
        }
        cache[Self.key(text, source, target)] = result
        return result
    }

    private func scheduleNext() {
        guard !running, let first = jobs.first else { return }
        running = true
        let source = Locale.Language(identifier: first.source)
        let target = Locale.Language(identifier: first.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    /// Called by `.translationTask` with a session for the current language pair.
    func run(_ session: TranslationSession) async {
        guard let config = configuration else { running = false; return }
        let batch = jobs.filter {
            Locale.Language(identifier: $0.source) == config.source && Locale.Language(identifier: $0.target) == config.target
        }
        let batchIds = Set(batch.map(\.id))
        jobs.removeAll { batchIds.contains($0.id) }
        for job in batch {
            do {
                let response = try await session.translate(job.text)
                job.continuation.resume(returning: response.targetText)
            } catch {
                job.continuation.resume(throwing: error)
            }
        }
        running = false
        scheduleNext()
    }

    private static func key(_ text: String, _ source: String, _ target: String) -> String {
        "\(source)>\(target):\(text)"
    }
}

struct TranslationHost: ViewModifier {
    let translator: AppleTranslator

    func body(content: Content) -> some View {
        content.translationTask(translator.configuration) { session in
            await translator.run(session)
        }
    }
}
