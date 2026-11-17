import SwiftUI
import PhotosUI

/// Аватар сотрудника: фото из профиля или инициалы.
struct Avatar: View {
    @EnvironmentObject var state: AppState
    let userId: String?
    var name: String = ""
    var size: CGFloat = 40
    var body: some View {
        let p = state.profile(userId)
        ZStack {
            Circle().fill(Theme.gold.opacity(0.16))
            if let a = p?.avatar, !a.isEmpty {
                AuthImage(path: a).frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(initials(p?.name ?? name)).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Theme.gold)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if p?.isBirthdayToday == true { Text("🎂").font(.system(size: size * 0.32)).offset(x: 2, y: 2) }
        }
    }
}

/// Выбор ответственного.
struct StaffPicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let title: String
    let selected: String?
    var allowNone = false
    let onPick: (String) -> Void
    var body: some View {
        NavigationStack {
            List {
                if allowNone {
                    Button { onPick(""); dismiss() } label: {
                        HStack { Text("Без ответственного").foregroundStyle(Theme.muted); Spacer(); if (selected ?? "").isEmpty { Image(systemName: "checkmark").foregroundStyle(Theme.gold) } }
                    }
                }
                ForEach(state.staff) { s in
                    Button { onPick(s.id); dismiss() } label: {
                        HStack(spacing: 12) {
                            Avatar(userId: s.id, size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name + (s.id == state.user?.id ? " (я)" : "")).foregroundStyle(Theme.text)
                                Text(roleName(s.role)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if s.id == selected { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
                        }
                    }
                }
            }
            .overlay { if state.staff.isEmpty { ProgressView() } }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .task { if state.staff.isEmpty { await state.refreshStaff() } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Строка «Ответственный» с аватаром — для заказа, заявки, задачи.
struct ResponsibleRow: View {
    @EnvironmentObject var state: AppState
    let userId: String?
    let name: String?
    let canChange: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let id = userId, !id.isEmpty { Avatar(userId: id, name: name ?? "", size: 36) }
                else { Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 26)).foregroundStyle(Theme.amber).frame(width: 36, height: 36) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ответственный").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text((name ?? "").isEmpty ? "Не назначен" : name!).font(.system(size: 16, weight: .semibold)).foregroundStyle((name ?? "").isEmpty ? Theme.amber : Theme.text)
                }
                Spacer()
                if canChange { Text("Изменить").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold) }
            }
        }
        .disabled(!canChange)
    }
}

// MARK: - Сотрудники и профиль

struct StaffListView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List(state.staff) { s in
            NavigationLink { StaffProfileView(staffId: s.id) } label: {
                HStack(spacing: 12) {
                    Avatar(userId: s.id, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name).font(.system(size: 16, weight: .semibold))
                        Text(roleName(s.role) + (s.isBirthdayToday ? " · сегодня день рождения 🎉" : "")).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .refreshable { await state.refreshStaff() }
        .navigationTitle("Сотрудники")
    }
}

struct StaffProfileView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    let staffId: String
    @State private var edit = false
    private var p: StaffProfile? { state.profile(staffId) }
    private var canEdit: Bool { staffId == state.user?.id || (state.isBoss && !(p?.role == "owner" && state.user?.role != "owner")) }

    var body: some View {
        List {
            if let p {
                Section {
                    VStack(spacing: 10) {
                        Avatar(userId: p.id, size: 110)
                        Text(p.name).font(.system(size: 22, weight: .bold))
                        Text(roleName(p.role)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section {
                    if !p.phone.isEmpty {
                        Button { if let u = URL(string: "tel:\(p.phone.filter { $0.isNumber || $0 == "+" })") { openURL(u) } } label: { LabeledContent("Телефон", value: p.phone) }
                    }
                    if !p.telegram.isEmpty {
                        Button { if let u = URL(string: "https://t.me/\(p.telegram)") { openURL(u) } } label: { LabeledContent("Telegram", value: "@" + p.telegram) }
                    }
                    if !p.birthdayText.isEmpty { LabeledContent("День рождения", value: p.birthdayText + (p.isBirthdayToday ? " 🎂" : "")) }
                    if !p.email.isEmpty { LabeledContent("Email", value: p.email) }
                }
                if p.id != state.user?.id {
                    Section {
                        Button { Task { await openChat(p) } } label: { Label("Написать в чат", systemImage: "bubble.left") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Профиль").navigationBarTitleDisplayMode(.inline)
        .toolbar { if canEdit { ToolbarItem(placement: .navigationBarTrailing) { Button("Изменить") { edit = true } } } }
        .sheet(isPresented: $edit) { if let p { ProfileEditView(profile: p) } }
    }

    private func openChat(_ p: StaffProfile) async {
        if let r = try? await API.shared.post("/api/chat.php?action=direct", ["user_id": Int(p.id) ?? 0], as: RoomIdResponse.self) {
            await state.refreshRooms()
            state.chatPath = [r.roomId]
            state.selectedTab = 3
        }
    }
}

/// Редактирование профиля: фото, имя, телефон, дата рождения, Telegram.
struct ProfileEditView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let profile: StaffProfile
    @State private var name = ""
    @State private var phone = ""
    @State private var telegram = ""
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Avatar(userId: profile.id, size: 96)
                        HStack(spacing: 16) {
                            PhotosPicker(selection: $photo, matching: .images) { Text("Выбрать фото") }
                            if !(state.profile(profile.id)?.avatar ?? "").isEmpty {
                                Button("Убрать", role: .destructive) { Task { await removePhoto() } }
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section("Данные") {
                    TextField("Имя и фамилия", text: $name)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                    HStack { Text("@").foregroundStyle(Theme.muted); TextField("Telegram", text: $telegram).textInputAutocapitalization(.never).autocorrectionDisabled() }
                    Toggle("Дата рождения", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Дата", selection: $birthday, in: ...Date(), displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ru_RU"))
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Профиль").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("Сохранить") } }.disabled(busy)
                }
            }
            .onAppear {
                name = profile.name; phone = profile.phone; telegram = profile.telegram
                if let d = profile.birthDate { hasBirthday = true; birthday = d }
            }
            .onChange(of: photo) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { await upload(img) }
                    photo = nil
                }
            }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        do {
            let r: StaffProfilesResponse = try await API.shared.post("/api/profile.php?action=update", [
                "id": Int(profile.id) ?? 0, "name": name, "phone": phone, "telegram": telegram,
                "birthday": hasBirthday ? f.string(from: birthday) : "",
            ])
            state.staff = r.staff
            if profile.id == state.user?.id { await state.loadMe() }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func upload(_ img: UIImage) async {
        busy = true; defer { busy = false }
        guard let data = img.scaledDown(maxSide: 1024).jpegData(compressionQuality: 0.85) else { return }
        do {
            let r: StaffProfilesResponse = try await API.shared.upload("/api/profile.php?action=avatar", fields: ["id": profile.id], fileField: "file", fileName: "avatar.jpg", mime: "image/jpeg", data: data)
            state.staff = r.staff
        } catch { self.error = error.localizedDescription }
    }

    private func removePhoto() async {
        do {
            let r: StaffProfilesResponse = try await API.shared.post("/api/profile.php?action=avatar-delete", ["id": Int(profile.id) ?? 0])
            state.staff = r.staff
        } catch { self.error = error.localizedDescription }
    }
}
