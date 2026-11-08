import Foundation
import Observation
import Supabase

/// App-wide state: auth session, the signed-in profile and the shared directory
/// of profiles, contacts and blocks.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable { case unconfigured, loading, signedOut, signedIn }

    let backend: Backend?
    private(set) var phase: Phase
    private(set) var me: Profile?
    private(set) var profiles: [UUID: Profile] = [:]
    private(set) var contacts: Set<UUID> = []
    private(set) var blocked: Set<UUID> = []
    var errorMessage: String?

    init() {
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseKey {
            backend = Backend(url: url, key: key)
            phase = .loading
        } else {
            backend = nil
            phase = .unconfigured
        }
    }

    func start() async {
        guard let backend else { return }
        for await (event, session) in backend.client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                if session != nil {
                    if me == nil { await refresh() }
                    phase = me == nil ? .signedOut : .signedIn
                } else {
                    phase = .signedOut
                }
            case .signedOut:
                me = nil
                profiles = [:]
                phase = .signedOut
            default:
                break
            }
        }
    }

    func refresh() async {
        guard let backend, let uid = backend.currentUserId else { return }
        do {
            async let all = backend.profiles()
            async let contactIds = backend.contactIds()
            async let blockedIds = backend.blockedIds()
            let list = try await all
            profiles = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            me = profiles[uid]
            contacts = try await contactIds
            blocked = try await blockedIds
        } catch {
            errorMessage = AppError.message(for: error)
        }
    }

    func profile(_ id: UUID) -> Profile? { profiles[id] }

    func name(_ id: UUID) -> String { profiles[id]?.name ?? "Onbekend" }

    var contactProfiles: [Profile] {
        contacts.compactMap { profiles[$0] }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Runs a backend action, shows a friendly error and refreshes the directory.
    @discardableResult
    func perform(_ action: (Backend) async throws -> Void) async -> Bool {
        guard let backend else { return false }
        do {
            try await action(backend)
            await refresh()
            return true
        } catch {
            errorMessage = AppError.message(for: error)
            return false
        }
    }

    func signOut() async {
        _ = await perform { try await $0.signOut() }
    }
}
