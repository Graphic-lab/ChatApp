import SwiftUI

@main
struct HeartToHeartApp: App {
    @State private var session = SessionStore()
    @State private var translator = AppleTranslator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(translator)
                .modifier(TranslationHost(translator: translator))
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        @Bindable var session = session
        Group {
            switch session.phase {
            case .unconfigured: SetupNeededView()
            case .loading: ProgressView()
            case .signedOut: AuthView()
            case .signedIn: MainTabs()
            }
        }
        .animation(.smooth, value: session.phase)
        .task { await session.start() }
        .alert("Let op", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}

struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill") { ChatsView() }
            Tab("Contacten", systemImage: "person.2.fill") { ContactsView() }
            Tab("Instellingen", systemImage: "gearshape.fill") { SettingsView() }
        }
    }
}
