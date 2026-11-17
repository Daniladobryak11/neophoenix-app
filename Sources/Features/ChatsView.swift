import SwiftUI

/// Чаты сотрудников — те же, что в CRM на сайте.
struct ChatsView: View {
    @EnvironmentObject var state: AppState
    @State private var showNew = false

    var body: some View {
        NavigationStack(path: $state.chatPath) {
            List {
                if let e = state.chatsError, state.rooms.isEmpty {
                    ErrorCard(text: e) { Task { await state.refreshRooms() } }.listRowBackground(Color.clear)
                } else if state.rooms.isEmpty {
                    EmptyCard(icon: "bubble.left.and.bubble.right", text: state.roomsLoaded ? "Чатов пока нет — нажмите ✎ справа вверху" : "Загружаю чаты…")
                        .listRowBackground(Color.clear)
                }
                ForEach(state.rooms) { r in
                    NavigationLink(value: r.id) { RoomRow(room: r, myId: state.user?.id ?? "") }
                        .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .refreshable { await state.refreshRooms() }
            .navigationTitle("Чаты")
            .navigationDestination(for: String.self) { id in ChatRoomView(roomId: id) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .sheet(isPresented: $showNew) { NewChatView() }
            .task { await state.refreshRooms() }
        }
    }
}

struct RoomRow: View {
    let room: ChatRoom
    let myId: String
    var body: some View {
        HStack(spacing: 12) {
            if room.kind == "group" {
                ZStack {
                    Circle().fill(Theme.gold.opacity(0.16))
                    Image(systemName: "person.3.fill").font(.system(size: 15)).foregroundStyle(Theme.gold)
                }
                .frame(width: 46, height: 46)
            } else {
                Avatar(userId: room.members.first { $0.id != myId }?.id, name: room.title, size: 46)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(room.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if let d = parseSQLDate(room.lastAt) { Text(shortTime(d)).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                }
                HStack {
                    Text(preview).font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    if room.unread > 0 {
                        Text("\(room.unread)").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.onGold)
                            .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22).background(Theme.goldFill, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    private var preview: String {
        if room.lastDeleted { return "Сообщение удалено" }
        guard let b = room.lastBody, !b.isEmpty else { return room.kind == "group" ? "\(room.memberCount) участн." : "Нет сообщений" }
        return (room.lastSenderId == myId ? "Вы: " : "") + b
    }
}

func shortTime(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU")
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "d MMM"
    return f.string(from: d)
}

/// Новый чат: личный с коллегой или группа.
struct NewChatView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var staff: [Staff] = []
    @State private var group = false
    @State private var title = ""
    @State private var picked = Set<String>()
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $group) {
                    Text("Личный").tag(false)
                    Text("Группа").tag(true)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if group {
                    Section("Название группы") { TextField("Например, «Склад»", text: $title) }
                }
                Section(group ? "Участники" : "С кем переписываться") {
                    if staff.isEmpty { ProgressView() }
                    ForEach(staff.filter { $0.id != state.user?.id }) { s in
                        Button {
                            if group { if picked.contains(s.id) { picked.remove(s.id) } else { picked.insert(s.id) } }
                            else { Task { await openDirect(s) } }
                        } label: {
                            HStack {
                                Text(initials(s.name)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.gold)
                                    .frame(width: 34, height: 34).background(Theme.gold.opacity(0.14), in: Circle())
                                VStack(alignment: .leading) {
                                    Text(s.name).foregroundStyle(Theme.text)
                                    Text(roleName(s.role)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if group { Image(systemName: picked.contains(s.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.gold) }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Новый чат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                if group {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") { Task { await createGroup() } }.disabled(busy || title.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                }
            }
            .task {
                do { let r: StaffResponse = try await API.shared.get("/api/chat.php?action=staff"); staff = r.users }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func openDirect(_ s: Staff) async {
        busy = true; defer { busy = false }
        do {
            let r: RoomIdResponse = try await API.shared.post("/api/chat.php?action=direct", ["user_id": Int(s.id) ?? 0])
            await state.refreshRooms()
            state.chatPath = [r.roomId]
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func createGroup() async {
        busy = true; defer { busy = false }
        do {
            let r: RoomIdResponse = try await API.shared.post("/api/chat.php?action=group", ["title": title.trimmingCharacters(in: .whitespaces), "user_ids": picked.compactMap { Int($0) }])
            await state.refreshRooms()
            state.chatPath = [r.roomId]
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

func roleName(_ r: String) -> String {
    switch r { case "owner": return "Владелец"; case "admin": return "Администратор"; default: return "Менеджер" }
}

