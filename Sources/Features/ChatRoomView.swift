import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreLocation

/// Переписка: обновляется каждые 3 секунды, пока экран открыт.
/// Долгое нажатие на сообщение — реакции, ответить, скопировать, изменить, удалить.
/// Скрепка — фото с камеры, из галереи, файл или геопозиция.
struct ChatRoomView: View {
    @EnvironmentObject var state: AppState
    let roomId: String
    @State private var messages: [ChatMessage] = []
    @State private var typing: [String] = []
    @State private var text = ""
    @State private var sending = false
    @State private var error: String?
    @State private var loaded = false
    @State private var replyTo: ChatMessage?
    @State private var editing: ChatMessage?
    @State private var confirmDelete: ChatMessage?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var viewer: ChatMessage?
    @State private var shareURL: URL?
    @StateObject private var locator = OneShotLocation()
    @StateObject private var recorder = VoiceRecorder()
    @State private var receipts: [Receipt] = []
    @State private var lastTypingSent = Date.distantPast
    @State private var forwarding: ChatMessage?
    @State private var showInfo = false
    @State private var search = ""
    @State private var searching = false
    @FocusState private var focused: Bool

    private var room: ChatRoom? { state.rooms.first { $0.id == roomId } }
    private var myId: String { state.user?.id ?? "" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if loaded && messages.isEmpty {
                        Text("Напишите первое сообщение").font(.system(size: 14)).foregroundStyle(Theme.muted).padding(.top, 40)
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                        row(i, m)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { withAnimation { searching.toggle(); if !searching { search = "" } } } label: { Image(systemName: "magnifyingglass") }
            }
            ToolbarItem(placement: .principal) {
                Button { showInfo = true } label: {
                VStack(spacing: 0) {
                    Text(room?.title ?? "Чат").font(.system(size: 16, weight: .semibold))
                    if !typing.isEmpty { Text(typing.joined(separator: ", ") + " печатает…").font(.system(size: 11)).foregroundStyle(Theme.green) }
                    else if room?.kind == "group" { Text("\(room?.memberCount ?? 0) участн. · инфо").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                    else { Text("профиль").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                }
                .foregroundStyle(Theme.text)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if searching {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Поиск в чате", text: $search).textInputAutocapitalization(.never)
                    if !search.isEmpty { Text("\(shown.count)").font(.system(size: 13)).foregroundStyle(Theme.muted) }
                }
                .padding(10).background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial)
            }
        }
        .sheet(isPresented: $showInfo) { ChatInfoView(roomId: roomId) }
        .sheet(item: $forwarding) { m in ForwardPicker(message: m, currentRoom: roomId) }
        .onChange(of: text) { t in
            guard editing == nil, !t.isEmpty, Date().timeIntervalSince(lastTypingSent) > 4 else { return }
            lastTypingSent = Date()
            Task { _ = try? await API.shared.post("/api/chat.php?action=typing", ["room_id": rid], as: OkResponse.self) }
        }
        .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(error ?? "") }
        .confirmationDialog("Удалить сообщение у всех?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let m = confirmDelete { Task { await delete(m) } } }
            Button("Отмена", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { await sendImage(img) }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in Task { await sendImage(img) } }.ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { Task { await sendFile(url) } }
        }
        .sheet(item: $viewer) { m in ImageViewer(message: m) }
        .sheet(item: Binding(get: { shareURL.map { URLBox(url: $0) } }, set: { shareURL = $0?.url })) { box in ShareSheet(items: [box.url]) }
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

    // MARK: строка переписки

    @ViewBuilder private func row(_ i: Int, _ m: ChatMessage) -> some View {
        let prev: ChatMessage? = i > 0 ? shown[i - 1] : nil
        if dayKey(m) != (prev.map { dayKey($0) } ?? "") {
            DayChip(title: dayTitle(m))
        }
        bubble(m, prev: prev)
    }

    private func bubble(_ m: ChatMessage, prev: ChatMessage?) -> some View {
        let isGroup = room?.kind == "group"
        let mine = m.senderId == myId
        let showName = isGroup && !mine && prev?.senderId != m.senderId
        return Bubble(message: m, mine: mine, showName: showName, showAvatar: isGroup && !mine, readState: readState(m),
                      onReact: { e in Task { await react(m, e) } },
                      onOpen: { Task { await open(m) } })
            .id(m.id)
            .contextMenu { menu(for: m) }
            .simultaneousGesture(swipeToReply(m))
    }

    private func swipeToReply(_ m: ChatMessage) -> some Gesture {
        DragGesture(minimumDistance: 25).onEnded { v in
            guard v.translation.width < -60, abs(v.translation.height) < 40, !m.deleted else { return }
            replyTo = m; editing = nil; focused = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: меню сообщения

    @ViewBuilder private func menu(for m: ChatMessage) -> some View {
        if !m.deleted {
            Section {
                ForEach(chatReactions, id: \.self) { e in
                    Button { Task { await react(m, e) } } label: {
                        Text(e + (m.reactions.contains { $0.emoji == e && $0.mine } ? "  ✓" : ""))
                    }
                }
            }
            Button { replyTo = m; editing = nil; focused = true } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") }
            if m.attachmentId == nil {
                Button { forwarding = m } label: { Label("Переслать", systemImage: "arrowshape.turn.up.right") }
            }
            if !m.isAutoLabel {
                Button { UIPasteboard.general.string = m.body } label: { Label("Скопировать", systemImage: "doc.on.doc") }
            }
            if m.senderId == myId && m.attachmentId == nil {
                Button { editing = m; replyTo = nil; text = m.body; focused = true } label: { Label("Изменить", systemImage: "pencil") }
            }
            if m.senderId == myId {
                Button(role: .destructive) { confirmDelete = m } label: { Label("Удалить", systemImage: "trash") }
            }
        }
    }

    // MARK: поле ввода

    private var composer: some View {
        VStack(spacing: 0) {
            if let r = replyTo ?? editing {
                HStack(spacing: 10) {
                    Rectangle().fill(Theme.gold).frame(width: 3, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(editing != nil ? "Изменение сообщения" : "Ответ: \(r.senderName)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gold)
                        Text(r.body).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                    Button { if editing != nil { text = "" }; replyTo = nil; editing = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if editing == nil {
                    Menu {
                        Button { showCamera = true } label: { Label("Камера", systemImage: "camera") }
                        Button { showPhotos = true } label: { Label("Фото из галереи", systemImage: "photo.on.rectangle") }
                        Button { showFiles = true } label: { Label("Файл", systemImage: "doc") }
                        Button { Task { await sendLocation() } } label: { Label("Геопозиция", systemImage: "location") }
                    } label: {
                        Image(systemName: "paperclip").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 40, height: 40)
                    }
                    .disabled(sending)
                }
                TextField("Сообщение", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && editing == nil {
                    Button { Task { await startVoice() } } label: {
                        Image(systemName: "mic.fill").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onGold)
                            .frame(width: 40, height: 40).background(Theme.goldFill, in: Circle())
                    }
                    .disabled(sending)
                } else {
                    Button { Task { await send() } } label: {
                        Group {
                            if sending { ProgressView().tint(Theme.onGold) }
                            else { Image(systemName: editing != nil ? "checkmark" : "arrow.up").font(.system(size: 17, weight: .bold)) }
                        }
                        .foregroundStyle(Theme.onGold)
                        .frame(width: 40, height: 40).background(Theme.goldFill, in: Circle())
                    }
                    .disabled(sending)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .overlay {
                if recorder.isRecording {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.red).frame(width: 10, height: 10)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(recorder.elapsedText).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        }
                        Spacer()
                        Button("Отмена") { recorder.cancel() }.foregroundStyle(Theme.red)
                        Button { Task { await finishVoice() } } label: {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onGold)
                                .frame(width: 40, height: 40).background(Theme.goldFill, in: Circle())
                        }
                    }
                    .padding(.horizontal, 16).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: сеть

    private var rid: Int { Int(roomId) ?? 0 }

    private var shown: [ChatMessage] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? messages : messages.filter { $0.body.lowercased().contains(q) || $0.senderName.lowercased().contains(q) }
    }
    private func dayKey(_ m: ChatMessage) -> String {
        guard let d = parseSQLDate(m.createdAt) else { return "" }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    private func dayTitle(_ m: ChatMessage) -> String {
        guard let d = parseSQLDate(m.createdAt) else { return "" }
        if Calendar.current.isDateInToday(d) { return "Сегодня" }
        if Calendar.current.isDateInYesterday(d) { return "Вчера" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM"
        return f.string(from: d)
    }
    /// 0 — не моё, 1 — отправлено ✓, 2 — прочитано ✓✓
    private func readState(_ m: ChatMessage) -> Int {
        guard m.senderId == myId else { return 0 }
        return receipts.contains { $0.read >= m.numericId } ? 2 : 1
    }

    private func startVoice() async {
        if let e = await recorder.start() { error = e }
    }
    private func finishVoice() async {
        guard let url = recorder.stop() else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), data.count > 1500 else { error = "Слишком короткое голосовое"; return }
        await upload(data: data, name: "voice.m4a", mime: "audio/mp4")
    }

    private func load(initial: Bool) async {
        do {
            let r: MessagesResponse = try await API.shared.get("/api/chat.php?action=messages&room_id=\(roomId)")
            if r.messages != messages { messages = r.messages }
            typing = r.typing ?? []
            receipts = r.receipts ?? []
            loaded = true
            if let last = r.messages.last, last.senderId != myId {
                _ = try? await API.shared.post("/api/chat.php?action=read", ["room_id": rid, "last_id": last.numericId], as: OkResponse.self)
            }
        } catch { if initial { self.error = error.localizedDescription } }
    }

    private func send() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; defer { sending = false }
        do {
            if let e = editing {
                _ = try await API.shared.post("/api/chat.php?action=edit-message", ["message_id": e.numericId, "body": body], as: OkResponse.self)
                editing = nil
            } else {
                var payload: [String: Any] = ["room_id": rid, "body": body]
                if let r = replyTo { payload["reply_to_id"] = r.numericId }
                _ = try await API.shared.post("/api/chat.php?action=send", payload, as: OkResponse.self)
                replyTo = nil
            }
            text = ""
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await load(initial: false)
        } catch { self.error = error.localizedDescription }
    }

    private func react(_ m: ChatMessage, _ emoji: String) async {
        do {
            _ = try await API.shared.post("/api/chat.php?action=react", ["message_id": m.numericId, "emoji": emoji], as: OkResponse.self)
            UISelectionFeedbackGenerator().selectionChanged()
            await load(initial: false)
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ m: ChatMessage) async {
        do {
            _ = try await API.shared.post("/api/chat.php?action=delete-message", ["message_id": m.numericId], as: OkResponse.self)
            await load(initial: false)
        } catch { self.error = error.localizedDescription }
    }

    private func sendImage(_ image: UIImage) async {
        let img = image.scaledDown(maxSide: 2000)
        guard let data = img.jpegData(compressionQuality: 0.82) else { return }
        await upload(data: data, name: "photo-\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg")
    }

    private func sendFile(_ url: URL) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { error = "Не удалось прочитать файл"; return }
        if data.count > 8 * 1024 * 1024 { error = "Файл больше 8 МБ — так много сервер не примет"; return }
        let ext = url.pathExtension.lowercased()
        let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        await upload(data: data, name: url.lastPathComponent, mime: mime)
    }

    private func upload(data: Data, name: String, mime: String) async {
        sending = true; defer { sending = false }
        do {
            _ = try await API.shared.upload("/api/chat.php?action=upload", fields: ["room_id": roomId], fileField: "file", fileName: name, mime: mime, data: data, as: OkResponse.self)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load(initial: false)
        } catch { self.error = error.localizedDescription }
    }

    private func sendLocation() async {
        sending = true
        let loc = await locator.request()
        sending = false
        guard let c = loc?.coordinate else { error = "Не удалось определить геопозицию. Разрешите доступ к геопозиции в Настройках → Нео Феникс."; return }
        let lat = String(format: "%.6f", c.latitude), lon = String(format: "%.6f", c.longitude)
        text = "📍 Я здесь: https://yandex.ru/maps/?pt=\(lon),\(lat)&z=17&l=map"
        await send()
    }

    private func open(_ m: ChatMessage) async {
        guard let id = m.attachmentId else { return }
        if m.attachmentIsImage { viewer = m; return }
        do {
            let (data, _) = try await API.shared.download("/api/chat-file.php?id=\(id)")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(m.attachmentName ?? "file")
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Пузырь сообщения

struct Bubble: View {
    let message: ChatMessage
    let mine: Bool
    let showName: Bool
    var showAvatar = false
    var readState = 0
    var onReact: (String) -> Void = { _ in }
    var onOpen: () -> Void = {}

    private var isVoice: Bool { (message.attachmentName ?? "").lowercased().hasSuffix(".m4a") }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer(minLength: 50) }
            if showAvatar { Avatar(userId: message.senderId, name: message.senderName, size: 28) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 4) {
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
                        if let aid = message.attachmentId {
                            if isVoice {
                                VoicePlayerView(path: "/api/chat-file.php?id=\(aid)")
                            } else if message.attachmentIsImage {
                                AuthImage(path: "/api/chat-file.php?id=\(aid)")
                                    .frame(maxWidth: 230, maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .onTapGesture(perform: onOpen)
                            } else {
                                Button(action: onOpen) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "doc.fill").font(.system(size: 22)).foregroundStyle(Theme.gold)
                                        Text(message.attachmentName ?? "Файл").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(2)
                                    }
                                }
                            }
                        }
                        if !message.body.isEmpty && !message.isAutoLabel {
                            Text(linkified(message.body)).font(.system(size: 16)).textSelection(.enabled)
                        }
                    }
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if message.edited && !message.deleted { Text("изм.").font(.system(size: 10)) }
                        if let d = parseSQLDate(message.createdAt) { Text(d.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)) }
                        if readState > 0 {
                            Image(systemName: readState == 2 ? "checkmark.circle.fill" : "checkmark")
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(readState == 2 ? Theme.gold : Theme.muted)
                        }
                    }
                    .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
                .background(mine ? Theme.gold.opacity(0.22) : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions, id: \.emoji) { r in
                            Button { onReact(r.emoji) } label: {
                                Text("\(r.emoji) \(r.count)").font(.system(size: 13))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(r.mine ? Theme.gold.opacity(0.3) : Theme.card2, in: Capsule())
                                    .foregroundStyle(Theme.text)
                            }
                        }
                    }
                }
            }
            if !mine { Spacer(minLength: 50) }
        }
    }

    /// Ссылки в тексте нажимаются (например, геопозиция).
    private func linkified(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = s as NSString
            for m in det.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                guard let url = m.url, let r = Range<AttributedString.Index>(m.range, in: a) else { continue }
                a[r].link = url
            }
        }
        return a
    }
}

// MARK: - Картинки и файлы с ключом сотрудника

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    func get(_ k: String) -> UIImage? { cache.object(forKey: k as NSString) }
    func set(_ k: String, _ v: UIImage) { cache.setObject(v, forKey: k as NSString) }
}

struct AuthImage: View {
    let path: String
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed { Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(Theme.muted).frame(width: 160, height: 120) }
            else { ProgressView().frame(width: 160, height: 120) }
        }
        .task(id: path) {
            if let c = ImageCache.shared.get(path) { image = c; return }
            do {
                let (data, _) = try await API.shared.download(path)
                if let img = UIImage(data: data) { ImageCache.shared.set(path, img); image = img } else { failed = true }
            } catch { failed = true }
        }
    }
}

struct ImageViewer: View {
    let message: ChatMessage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let id = message.attachmentId { AuthImage(path: "/api/chat-file.php?id=\(id)").scaledToFit() }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

struct URLBox: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension UIImage {
    func scaledDown(maxSide: CGFloat) -> UIImage {
        let m = max(size.width, size.height)
        guard m > maxSide else { return self }
        let k = maxSide / m
        let newSize = CGSize(width: size.width * k, height: size.height * k)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

/// Одноразовое определение геопозиции для отправки в чат.
@MainActor
final class OneShotLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func request() async -> CLLocation? {
        if cont != nil { return nil }
        return await withCheckedContinuation { c in
            cont = c
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(nil)
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ l: CLLocation?) { cont?.resume(returning: l); cont = nil }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            guard self.cont != nil else { return }
            switch m.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in self.finish(l) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

struct DayChip: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Theme.card, in: Capsule())
            .padding(.vertical, 6)
    }
}
