import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .symbolEffect(.breathe)
                VStack(spacing: 6) {
                    Text("Heart to Heart")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                    Text("Praat in je eigen taal. Je partner hoort de hare.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                    if codeSent {
                        TextField("6-cijferige code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(.title2.monospacedDigit())
                            .multilineTextAlignment(.center)
                            .padding()
                            .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text("Code verstuurd naar \(email)").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        TextField("E-mailadres", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if busy { ProgressView() } else { Text(codeSent ? "Inloggen" : "Stuur code") }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .glass(in: Capsule(), tint: .accentColor, interactive: true)
                    .disabled(busy || (codeSent ? code.count < 6 : !email.contains("@")))
                    if codeSent {
                        Button("Ander e-mailadres") { codeSent = false; code = "" }.font(.footnote)
                    }
                }
                .padding(.horizontal, 28)
                Spacer()
                Text("Alleen op uitnodiging.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
    }

    private func submit() async {
        guard let backend = session.backend else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            if codeSent {
                try await backend.verify(email: email, code: code)
            } else {
                try await backend.sendCode(to: email)
                codeSent = true
            }
        } catch let failure {
            error = AppError.message(for: failure)
        }
    }
}

struct SetupNeededView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Backend niet ingesteld", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("Vul ios/Config/Secrets.xcconfig in met je Supabase URL en sleutel. Zie buildkit/README.md.")
        }
    }
}
