import SwiftUI

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var server = API.shared.server
    @State private var busy = false
    @State private var error: String?
    @State private var showServer = false
    @FocusState private var focus: Field?
    enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Phoenix").resizable().scaledToFit().frame(width: 150).padding(.top, 60)
                VStack(spacing: 6) {
                    Text("Нео Феникс").font(.system(size: 30, weight: .bold))
                    Text("Приложение для сотрудников").font(.system(size: 15)).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next)
                        .onSubmit { focus = .password }
                        .fieldStyle()
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password).submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .fieldStyle()
                }
                if let error {
                    Text(error).font(.system(size: 14)).foregroundStyle(Theme.red).multilineTextAlignment(.center)
                }
                Button { Task { await submit() } } label: {
                    if busy { ProgressView().tint(Theme.onGold) } else { Text("Войти") }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(busy || email.isEmpty || password.isEmpty)

                Text("Тот же email и пароль, что и в CRM на сайте.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)

                DisclosureGroup("Сервер", isExpanded: $showServer) {
                    TextField("https://neophoenix.ru", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .fieldStyle().padding(.top, 8)
                }
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
    }

    private func submit() async {
        guard !busy else { return }
        busy = true; error = nil
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = API.defaultServer }
        if !s.hasPrefix("https://") { s = "https://" + s.replacingOccurrences(of: "http://", with: "") }
        while s.hasSuffix("/") { s.removeLast() }
        API.shared.server = s
        do { try await state.login(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password) }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}

extension View {
    func fieldStyle() -> some View {
        self.font(.system(size: 17))
            .padding(.horizontal, 16).frame(height: 54)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LockView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Phoenix").resizable().scaledToFit().frame(width: 140)
            Text("Нео Феникс").font(.system(size: 26, weight: .bold))
            Spacer()
            Button { Task { await state.unlockWithFaceID() } } label: {
                Label("Войти по Face ID", systemImage: "faceid")
            }
            .buttonStyle(GoldButtonStyle())
            Button("Выйти из аккаунта") { state.signOutLocally() }
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 24)
        .task { await state.unlockWithFaceID() }
    }
}
