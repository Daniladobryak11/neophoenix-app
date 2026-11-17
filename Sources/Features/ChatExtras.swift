import SwiftUI
import AVFoundation

// MARK: - Информация о чате: участники, название, выйти, удалить

struct ChatInfoView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let roomId: String
    @State private var title = ""
    @State private var addPick = false
    @State private var confirm: String?
    @State private var error: String?
    @State private var members: [Staff] = []

    private var room: ChatRoom? { state.rooms.first { $0.id == roomId } }
    private var isGroup: Bool { room?.kind == "group" }
    private var canManage: Bool { room?.createdBy == state.user?.id || state.isBoss }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        if isGroup {
                            ZStack { Circle().fill(Theme.gold.opacity(0.16)); Image(systemName: "person.3.fill").font(.system(size: 30)).foregroundStyle(Theme.gold) }.frame(width: 84, height: 84)
                        } else {
                            Avatar(userId: members.first { $0.id != state.user?.id }?.id, name: room?.title ?? "", size: 84)
                        }
                        Text(room?.title ?? "Чат").font(.system(size: 20, weight: .bold))
                        if isGroup { Text("\(members.count) участн.").foregroundStyle(Theme.muted) }
                    }
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
                if isGroup && canManage {
                    Section("Название") {
                        HStack {
                            TextField("Название группы", text: $title)
                            Button("Сохранить") { Task { await act("rename", ["title": title]) } }
                                .disabled(title.trimmingCharacters(in: .whitespaces).count < 2 || title == room?.title)
                        }
                    }
                }
                Section(isGroup ? "Участники" : "Собеседник") {
                    ForEach(members) { m in
                        NavigationLink { StaffProfileView(staffId: m.id) } label: {
                            HStack(spacing: 12) {
                                Avatar(userId: m.id, name: m.name, size: 36)
                                VStack(alignment: .leading) {
                                    Text(m.name + (m.id == state.user?.id ? " (я)" : ""))
                                    Text(roleName(m.role)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .swipeActions {
                            if isGroup && canManage && m.id != state.user?.id {
                                Button("Убрать", role: .destructive) { Task { await act("remove-member", ["user_id": Int(m.id) ?? 0]) } }
                            }
                        }
                    }
                    if isGroup && canManage {
                        Button { addPick = true } label: { Label("Добавить участника", systemImage: "person.badge.plus") }
                    }
                }
                Section {
                    if isGroup { Button("Покинуть группу", role: .destructive) { confirm = "leave" } }
                    if !isGroup || canManage { Button(isGroup ? "Удалить группу у всех" : "Удалить чат", role: .destructive) { confirm = "delete-room" } }
                }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("О чате").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear { title = room?.title ?? ""; members = room?.members ?? [] }
            .sheet(isPresented: $addPick) {
                StaffPicker(title: "Добавить в группу", selected: nil) { id in Task { await act("add-member", ["user_id": Int(id) ?? 0]) } }
            }
            .confirmationDialog(confirm == "leave" ? "Покинуть группу?" : "Удалить чат со всей перепиской?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                Button(confirm == "leave" ? "Покинуть" : "Удалить", role: .destructive) {
                    let a = confirm ?? ""
                    Task { await act(a, [:]); state.chatPath = []; dismiss() }
                }
            }
        }
    }

    private func act(_ action: String, _ extra: [String: Any]) async {
        var body = extra; body["room_id"] = Int(roomId) ?? 0
        do {
            _ = try await API.shared.post("/api/chat.php?action=\(action)", body, as: OkResponse.self)
            await state.refreshRooms()
            members = room?.members ?? members
            UISelectionFeedbackGenerator().selectionChanged()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Переслать сообщение в другой чат

struct ForwardPicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    let currentRoom: String
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.red) }
                ForEach(state.rooms.filter { $0.id != currentRoom }) { r in
                    Button { Task { await forward(to: r) } } label: { RoomRow(room: r, myId: state.user?.id ?? "") }
                }
            }
            .navigationTitle("Переслать в…").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }
    private func forward(to r: ChatRoom) async {
        do {
            _ = try await API.shared.post("/api/chat.php?action=forward", ["message_id": message.numericId, "target_room_id": Int(r.id) ?? 0], as: OkResponse.self)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await state.refreshRooms()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Голосовые сообщения

@MainActor
final class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    private var recorder: AVAudioRecorder?
    private var startedAt = Date()
    private var url: URL?

    var elapsedText: String {
        let s = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Возвращает текст ошибки или nil.
    func start() async -> String? {
        let session = AVAudioSession.sharedInstance()
        let granted: Bool = await withCheckedContinuation { c in session.requestRecordPermission { c.resume(returning: $0) } }
        guard granted else { return "Разрешите доступ к микрофону: Настройки → Нео Феникс → Микрофон." }
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            let r = try AVAudioRecorder(url: u, settings: settings)
            r.record(forDuration: 300)
            recorder = r; url = u; startedAt = Date(); isRecording = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return nil
        } catch { return "Не удалось начать запись" }
    }

    func stop() -> URL? {
        recorder?.stop(); recorder = nil; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return url
    }

    func cancel() {
        if let u = stop() { try? FileManager.default.removeItem(at: u) }
        url = nil
    }
}

@MainActor
final class VoicePlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var loading = false
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(path: String) async {
        if let p = player {
            if p.isPlaying { p.pause(); playing = false } else { activate(); p.play(); playing = true; tick() }
            return
        }
        loading = true; defer { loading = false }
        guard let res = try? await API.shared.download(path), let p = try? AVAudioPlayer(data: res.0) else { return }
        p.delegate = self
        player = p; duration = p.duration
        activate(); p.play(); playing = true; tick()
    }
    private func activate() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    private func tick() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
                if !p.isPlaying { self.timer?.invalidate() }
            }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false; self.progress = 0 }
    }
}

struct VoicePlayerView: View {
    let path: String
    @StateObject private var pb = VoicePlayback()
    var body: some View {
        HStack(spacing: 10) {
            Button { Task { await pb.toggle(path: path) } } label: {
                ZStack {
                    Circle().fill(Theme.goldFill)
                    if pb.loading { ProgressView().tint(Theme.onGold) }
                    else { Image(systemName: pb.playing ? "pause.fill" : "play.fill").foregroundStyle(Theme.onGold) }
                }
                .frame(width: 38, height: 38)
            }
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.muted.opacity(0.3))
                        Capsule().fill(Theme.gold).frame(width: g.size.width * pb.progress)
                    }
                }
                .frame(height: 4)
                Text(pb.duration > 0 ? String(format: "%d:%02d", Int(pb.duration) / 60, Int(pb.duration) % 60) : "Голосовое")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .frame(width: 140)
        }
    }
}
