import Foundation

/// One microphone button, two gestures (ported from the web POC):
/// - hold: records while pressed, stops on release
/// - short tap: latches recording on; the next tap stops it
struct RecordingGesture {
    enum State: Equatable {
        case idle
        case pressing(since: Date)
        case latched
        case stopping
    }

    enum Action: Equatable { case start, stop }

    static let holdThreshold: TimeInterval = 0.35

    private(set) var state: State = .idle

    mutating func pressDown(at now: Date = Date()) -> Action? {
        switch state {
        case .idle:
            state = .pressing(since: now)
            return .start
        case .latched:
            state = .stopping
            return .stop
        case .pressing, .stopping:
            return nil
        }
    }

    mutating func pressUp(at now: Date = Date()) -> Action? {
        switch state {
        case .pressing(let since):
            if now.timeIntervalSince(since) < Self.holdThreshold {
                state = .latched
                return nil
            }
            state = .idle
            return .stop
        case .stopping:
            state = .idle
            return nil
        case .idle, .latched:
            return nil
        }
    }

    mutating func reset() { state = .idle }
}
