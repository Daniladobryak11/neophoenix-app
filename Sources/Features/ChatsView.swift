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
            ZStack {
                Circle().fill(Theme.gold.opacity(0.16))
                if room.kind == "group" { Image(systemName: "person.3.fill").font(.system(size: 15)).foregroundStyle(Theme.gold) }
                else { Text(initials(room.title)).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.gold) }
            }
            .frame(width: 46, height: 46)
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

/// Переписка: обновляется каждые 3 секунды, пока экран открыт.
struct ChatRoomView: View {
    @EnvironmentObject var state: AppState
    let roomId: String
    @State private var messages: [ChatMessage] = []
    @State private var typing: [String] = []
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var room: ChatRoom? { state.rooms.first { $0.id == roomId } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if loaded && messages.isEmpty {
                        Text("Напишите первое сообщение").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.top, 40)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                        let showName = room?.kind == "group" && m.senderId != state.user?.id && (i == 0 || messages[i - 1].senderId != m.senderId)
                        Bubble(message: m, mine: m.senderId == state.user?.id, showName: showName).id(m.id)
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg)
            .onChange(of: messages.count) { _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: focused) { f in if f { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("bottom", anchor: .bottom) } } }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(room?.title ?? "Чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(room?.title ?? "Чат").font(.system(size: 16, weight: .semibold))
                    if !typing.isEmpty { Text(typing.joined(separator: ", ") + " печатает…").font(.system(size: 11)).foregroundStyle(Theme.green) }
                    else if room?.kind == "group" { Text("\(room?.memberCount ?? 0) участн.").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
            }
        }
        .alert("Не отправилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(error ?? "") }
        .task {
            await load(initial: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled { break }
                await load(initial: false)
            }
        }
        .onDisappear { Task { await state.refreshRooms() } }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Сообщение", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Button { Task { await send() } } label: {
                Image(systemName: sending ? "hourglass" : "arrow.up")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onGold)
                    .frame(width: 40, height: 40).background(Theme.goldFill, in: Circle())
            }
            .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func load(initial: Bool) async {
        do {
            let r: MessagesResponse = try await API.shared.get("/api/chat.php?action=messages&room_id=\(roomId)")
            if r.messages != messages { messages = r.messages }
            typing = r.typing ?? []
            loaded = true
            if let last = r.messages.last, last.senderId != state.user?.id {
                _ = try? await API.shared.post("/api/chat.php?action=read", ["room_id": Int(roomId) ?? 0, "last_id": last.numericId], as: OkResponse.self)
            }
        } catch { if initial { self.error = error.localizedDescription } }
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; defer { sending = false }
        do {
            _ = try await API.shared.post("/api/chat.php?action=send", ["room_id": Int(roomId) ?? 0, "body": body], as: OkResponse.self)
            text = ""
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await load(initial: false)
        } catch { self.error = error.localizedDescription }
    }
}

struct Bubble: View {
    let message: ChatMessage
    let mine: Bool
    let showName: Bool
    var body: some View {
        HStack {
            if mine { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 3) {
                if showName { Text(message.senderName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gold) }
                if let rb = message.replyBody, !rb.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.replySender ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gold)
                        Text(rb).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                    .padding(.leading, 8)
                    .overlay(Rectangle().fill(Theme.gold).frame(width: 2), alignment: .leading)
                }
                if message.deleted {
                    Text("Сообщение удалено").italic().foregroundStyle(Theme.muted)
                } else {
                    if let a = message.attachmentName, !a.isEmpty {
                        Label(a, systemImage: message.attachmentIsImage ? "photo" : "doc").font(.system(size: 14)).foregroundStyle(Theme.gold)
                    }
                    if !message.body.isEmpty { Text(message.body).font(.system(size: 16)).textSelection(.enabled) }
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if message.edited { Text("изм.").font(.system(size: 10)) }
                    if let d = parseSQLDate(message.createdAt) { Text(d.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)) }
                }
                .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            .background(mine ? Theme.gold.opacity(0.22) : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !mine { Spacer(minLength: 50) }
        }
    }
}
