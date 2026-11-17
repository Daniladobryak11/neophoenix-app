import Foundation

/// Сервер отдаёт id то числом, то строкой — читаем любой вариант.
extension KeyedDecodingContainer {
    func flexString(_ k: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: k) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return String(Int(d)) }
        return nil
    }
    func flexInt(_ k: Key) -> Int {
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i }
        if let s = try? decodeIfPresent(String.self, forKey: k), let i = Int(s) { return i }
        if let b = try? decodeIfPresent(Bool.self, forKey: k) { return b ? 1 : 0 }
        return 0
    }
}

/// Даты чата приходят как «2026-11-17 11:56:11» в UTC.
func parseSQLDate(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s) ?? parseISO(s)
}

// MARK: - Сотрудники и чаты

struct Staff: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String
    enum K: String, CodingKey { case id, name, role }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""
        name = c.flexString(.name) ?? ""
        role = c.flexString(.role) ?? ""
    }
}
struct StaffResponse: Decodable { let ok: Bool; let users: [Staff] }

struct ChatRoom: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let createdBy: String
    let unread: Int
    let memberCount: Int
    let lastBody: String?
    let lastAt: String?
    let lastSenderId: String?
    let lastDeleted: Bool
    let members: [Staff]
    enum K: String, CodingKey { case id, kind, title, created_by, unread_count, member_count, last_body, last_at, last_sender_id, last_deleted, members }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""
        kind = c.flexString(.kind) ?? "group"
        title = c.flexString(.title) ?? "Чат"
        createdBy = c.flexString(.created_by) ?? ""
        unread = c.flexInt(.unread_count)
        memberCount = c.flexInt(.member_count)
        lastBody = c.flexString(.last_body)
        lastAt = c.flexString(.last_at)
        lastSenderId = c.flexString(.last_sender_id)
        lastDeleted = c.flexString(.last_deleted) != nil
        members = (try? c.decodeIfPresent([Staff].self, forKey: .members)) ?? []
    }
}
struct RoomsResponse: Decodable { let ok: Bool; let rooms: [ChatRoom] }
struct RoomIdResponse: Decodable {
    let ok: Bool
    let roomId: String
    enum K: String, CodingKey { case ok, room_id }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        ok = (try? c.decode(Bool.self, forKey: .ok)) ?? false
        roomId = c.flexString(.room_id) ?? ""
    }
}

struct ChatMessage: Decodable, Hashable, Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let body: String
    let createdAt: String?
    let edited: Bool
    let deleted: Bool
    let replyBody: String?
    let replySender: String?
    let attachmentId: String?
    let attachmentName: String?
    let attachmentIsImage: Bool
    enum K: String, CodingKey { case id, sender_id, sender_name, body, created_at, edited_at, deleted_at, reply_body, reply_sender_name, attachment_id, attachment_name, attachment_is_image }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""
        senderId = c.flexString(.sender_id) ?? ""
        senderName = c.flexString(.sender_name) ?? ""
        body = c.flexString(.body) ?? ""
        createdAt = c.flexString(.created_at)
        edited = c.flexString(.edited_at) != nil
        deleted = c.flexString(.deleted_at) != nil
        replyBody = c.flexString(.reply_body)
        replySender = c.flexString(.reply_sender_name)
        attachmentId = c.flexString(.attachment_id)
        attachmentName = c.flexString(.attachment_name)
        attachmentIsImage = c.flexInt(.attachment_is_image) == 1
    }
    var numericId: Int { Int(id) ?? 0 }
}
struct Receipt: Decodable, Hashable {
    let name: String
    let read: Int
    enum K: String, CodingKey { case name, read }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        name = c.flexString(.name) ?? ""
        read = c.flexInt(.read)
    }
}
struct MessagesResponse: Decodable {
    let ok: Bool
    let messages: [ChatMessage]
    let receipts: [Receipt]?
    let typing: [String]?
}

// MARK: - Смена

struct Shift: Decodable, Hashable {
    let id: String
    let start: String
    let end: String?
    let startIso: String?
    let minutes: Int
    enum K: String, CodingKey { case id, start, end, startIso, minutes }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""
        start = c.flexString(.start) ?? ""
        end = c.flexString(.end)
        startIso = c.flexString(.startIso)
        minutes = c.flexInt(.minutes)
    }
}
struct WorkSummary: Decodable, Hashable {
    let minutes: Int
    let shifts: Int
    enum K: String, CodingKey { case minutes, shifts }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        minutes = c.flexInt(.minutes)
        shifts = c.flexInt(.shifts)
    }
}
struct WorkWindow: Decodable, Hashable { let open: String; let close: String; let inWindow: Bool }
struct WorkStatus: Decodable, Hashable {
    let ok: Bool
    let window: WorkWindow?
    let open: Shift?
    let today: WorkSummary?
    let month: WorkSummary?
}

func hoursText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
}

// MARK: - Заявки

struct Opt: Hashable, Identifiable { let id: String; let label: String }
let leadKinds = [Opt(id: "callback", label: "Перезвонить"), Opt(id: "question", label: "Вопрос"), Opt(id: "fitment", label: "Подбор"), Opt(id: "product", label: "Вопрос о товаре")]
let leadSources = ["Авито", "Звонок", "Мессенджер"]
let leadStatuses = [Opt(id: "new", label: "Новая"), Opt(id: "work", label: "В работе"), Opt(id: "done", label: "Обработана"), Opt(id: "spam", label: "Спам")]
