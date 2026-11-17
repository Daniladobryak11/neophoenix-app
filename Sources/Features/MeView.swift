import SwiftUI
import LocalAuthentication

struct MeView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Text(initials(state.user?.name ?? "")).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.gold)
                            .frame(width: 52, height: 52).background(Theme.gold.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.user?.name ?? "—").font(.system(size: 18, weight: .semibold))
                            Text(state.user?.roleLabel ?? "").font(.system(size: 14)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Смена") {
                    Label("Начать и закончить смену — в следующей версии", systemImage: "clock")
                        .foregroundStyle(Theme.muted).font(.system(size: 14))
                }
                Section("Настройки") {
                    Toggle(isOn: Binding(get: { state.faceIDEnabled }, set: { setFaceID($0) })) {
                        Label("Вход по Face ID", systemImage: "faceid")
                    }
                    Picker(selection: $state.theme) {
                        Text("Автоматически").tag("auto")
                        Text("Светлая").tag("light")
                        Text("Тёмная").tag("dark")
                    } label: { Label("Тема", systemImage: "circle.lefthalf.filled") }
                }
                Section {
                    LabeledContent("Сервер", value: API.shared.server.replacingOccurrences(of: "https://", with: ""))
                    if let d = state.lastSync {
                        LabeledContent("Обновлено", value: d.formatted(date: .omitted, time: .shortened))
                    }
                    LabeledContent("Версия", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "")
                }
                Section {
                    Button("Выйти", role: .destructive) { confirmLogout = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Я")
            .confirmationDialog("Выйти из аккаунта на этом iPhone?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await state.logout() } }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func setFaceID(_ on: Bool) {
        guard on else { state.faceIDEnabled = false; return }
        let ctx = LAContext()
        Task {
            if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Включить вход по Face ID")) == true {
                await MainActor.run { state.faceIDEnabled = true }
            }
        }
    }
}
