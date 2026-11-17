import SwiftUI
import LocalAuthentication

struct MeView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { StaffProfileView(staffId: state.user?.id ?? "") } label: {
                        HStack(spacing: 14) {
                            Avatar(userId: state.user?.id, name: state.user?.name ?? "", size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.me?.name ?? state.user?.name ?? "—").font(.system(size: 18, weight: .semibold))
                                Text((state.user?.roleLabel ?? "") + " · мой профиль").font(.system(size: 14)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    NavigationLink { StaffListView() } label: { Label("Сотрудники", systemImage: "person.2") }
                }
                Section {
                    ShiftCard().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
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
            .refreshable { await state.refreshWork() }
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
