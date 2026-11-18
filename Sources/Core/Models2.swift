import Foundation
import SwiftUI

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
    let systemKey: String?
    enum K: String, CodingKey { case id, kind, title, created_by, unread_count, member_count, last_body, last_at, last_sender_id, last_deleted, members, system_key }
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
        systemKey = c.flexString(.system_key)
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
    let reactions: [Reaction]
    let shipmentId: String?
    let shipStatus: String?
    let shipPackedBy: String?
    let shipPackedAt: String?
    let shipSentBy: String?
    let shipSentAt: String?
    let shipCancelReason: String?
    let shipKind: String?
    let shipReceivedBy: String?
    let shipReceivedAt: String?
    let shipCheckedBy: String?
    let shipCheckedAt: String?
    let shipCheckResult: String?
    let shipCheckComment: String?
    let shipPhotos: [String]
    enum K: String, CodingKey { case id, sender_id, sender_name, body, created_at, edited_at, deleted_at, reply_body, reply_sender_name, attachment_id, attachment_name, attachment_is_image, reactions,
                                shipment_id, ship_status, ship_packed_by, ship_packed_at, ship_sent_by, ship_sent_at, ship_cancel_reason,
                                ship_kind, ship_received_by, ship_received_at, ship_checked_by, ship_checked_at, ship_check_result, ship_check_comment, ship_photos }
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
        reactions = (try? c.decodeIfPresent([Reaction].self, forKey: .reactions)) ?? []
        shipmentId = c.flexString(.shipment_id); shipStatus = c.flexString(.ship_status)
        shipPackedBy = c.flexString(.ship_packed_by); shipPackedAt = c.flexString(.ship_packed_at)
        shipSentBy = c.flexString(.ship_sent_by); shipSentAt = c.flexString(.ship_sent_at)
        shipCancelReason = c.flexString(.ship_cancel_reason)
        shipKind = c.flexString(.ship_kind)
        shipReceivedBy = c.flexString(.ship_received_by); shipReceivedAt = c.flexString(.ship_received_at)
        shipCheckedBy = c.flexString(.ship_checked_by); shipCheckedAt = c.flexString(.ship_checked_at)
        shipCheckResult = c.flexString(.ship_check_result); shipCheckComment = c.flexString(.ship_check_comment)
        shipPhotos = (c.flexString(.ship_photos) ?? "").split(separator: ",").map(String.init)
    }
    /// Подпись к файлу сервер пишет сам («📷 имя.jpg») — её не показываем отдельно.
    var isAutoLabel: Bool { attachmentId != nil && (body.hasPrefix("📷 ") || body.hasPrefix("📎 ") || body.hasPrefix("🎤 ")) }
    var numericId: Int { Int(id) ?? 0 }
}
struct Reaction: Decodable, Hashable {
    let emoji: String
    let count: Int
    let mine: Bool
    enum K: String, CodingKey { case emoji, count, mine }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        emoji = c.flexString(.emoji) ?? ""
        count = c.flexInt(.count)
        mine = c.flexInt(.mine) == 1
    }
}
let chatReactions = ["👍", "❤️", "✅", "🔥"]

struct Product: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let article: String?
    let price: Double
    let stock: Int
    enum K: String, CodingKey { case id, name, article, price, stock }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""
        name = c.flexString(.name) ?? ""
        article = c.flexString(.article)
        if let p = try? c.decodeIfPresent(Double.self, forKey: .price) { price = p }
        else { price = Double(c.flexString(.price) ?? "") ?? 0 }
        stock = c.flexInt(.stock)
    }
}
struct CatalogResponse: Decodable {
    struct Payload: Decodable { let products: [Product] }
    let ok: Bool
    let data: Payload?
}
struct CreatedOrderResponse: Decodable {
    let ok: Bool
    let id: String?
    let orders: [Order]?
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

// MARK: - Профиль сотрудника

struct StaffProfile: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let role: String
    let email: String
    let phone: String
    let birthday: String
    let telegram: String
    let avatar: String
    enum K: String, CodingKey { case id, name, role, email, phone, birthday, telegram, avatar }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""; name = c.flexString(.name) ?? ""; role = c.flexString(.role) ?? ""
        email = c.flexString(.email) ?? ""; phone = c.flexString(.phone) ?? ""
        birthday = c.flexString(.birthday) ?? ""; telegram = c.flexString(.telegram) ?? ""; avatar = c.flexString(.avatar) ?? ""
    }
    var birthDate: Date? {
        guard !birthday.isEmpty else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: birthday)
    }
    var birthdayText: String {
        guard let d = birthDate else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM yyyy"
        return f.string(from: d)
    }
    var isBirthdayToday: Bool {
        guard let d = birthDate else { return false }
        let cal = Calendar.current
        return cal.component(.day, from: d) == cal.component(.day, from: Date()) && cal.component(.month, from: d) == cal.component(.month, from: Date())
    }
}
struct StaffProfilesResponse: Decodable { let ok: Bool; let staff: [StaffProfile] }

// MARK: - Задачи

struct TaskCan: Decodable, Hashable {
    let edit: Bool, start: Bool, finish: Bool, accept: Bool, ret: Bool, defer_: Bool, check: Bool, comment: Bool, delete: Bool
    enum K: String, CodingKey { case edit, start, finish, accept, ret = "return", defer_ = "defer", check, comment, delete }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        func b(_ k: K) -> Bool { c.flexInt(k) == 1 }
        edit = b(.edit); start = b(.start); finish = b(.finish); accept = b(.accept); ret = b(.ret)
        defer_ = b(.defer_); check = b(.check); comment = b(.comment); delete = b(.delete)
    }
}
struct CheckItem: Decodable, Hashable, Identifiable {
    let id: String; let text: String; let done: Bool
    enum K: String, CodingKey { case id, text, done }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""; text = c.flexString(.text) ?? ""; done = c.flexInt(.done) == 1
    }
}
struct FeedItem: Decodable, Hashable, Identifiable {
    let id: String; let kind: String; let userId: String; let name: String; let body: String; let createdAt: String
    enum K: String, CodingKey { case id, kind, userId, name, body, createdAt }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""; kind = c.flexString(.kind) ?? ""; userId = c.flexString(.userId) ?? ""
        name = c.flexString(.name) ?? ""; body = c.flexString(.body) ?? ""; createdAt = c.flexString(.createdAt) ?? ""
    }
}
struct TaskItem: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let description: String
    let status: String
    let statusLabel: String
    let priority: String
    let deadline: String
    let deadlineLocal: String
    let overdue: Bool
    let creatorId: String
    let creatorName: String
    let responsibleId: String
    let responsibleName: String
    let orderId: String
    let orderNumber: String
    let checkTotal: Int
    let checkDone: Int
    let comments: Int
    let checklist: [CheckItem]
    let feed: [FeedItem]
    let can: TaskCan?
    enum K: String, CodingKey { case id, title, description, status, statusLabel, priority, deadline, deadlineLocal, overdue, creatorId, creatorName, responsibleId, responsibleName, orderId, orderNumber, checkTotal, checkDone, comments, checklist, feed, can }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""; title = c.flexString(.title) ?? ""; description = c.flexString(.description) ?? ""
        status = c.flexString(.status) ?? "new"; statusLabel = c.flexString(.statusLabel) ?? ""; priority = c.flexString(.priority) ?? "normal"
        deadline = c.flexString(.deadline) ?? ""; deadlineLocal = c.flexString(.deadlineLocal) ?? ""; overdue = c.flexInt(.overdue) == 1
        creatorId = c.flexString(.creatorId) ?? ""; creatorName = c.flexString(.creatorName) ?? ""
        responsibleId = c.flexString(.responsibleId) ?? ""; responsibleName = c.flexString(.responsibleName) ?? ""
        orderId = c.flexString(.orderId) ?? ""; orderNumber = c.flexString(.orderNumber) ?? ""
        checkTotal = c.flexInt(.checkTotal); checkDone = c.flexInt(.checkDone); comments = c.flexInt(.comments)
        checklist = (try? c.decodeIfPresent([CheckItem].self, forKey: .checklist)) ?? []
        feed = (try? c.decodeIfPresent([FeedItem].self, forKey: .feed)) ?? []
        can = try? c.decodeIfPresent(TaskCan.self, forKey: .can)
    }
    var isOpen: Bool { status != "done" }
    var deadlineDate: Date? { parseISO(deadline) }
}
struct TasksResponse: Decodable { let ok: Bool; let tasks: [TaskItem] }
struct TaskResponse: Decodable { let ok: Bool; let task: TaskItem }

func taskStatusColor(_ s: String) -> Color {
    switch s { case "new": return Theme.blue; case "work": return Theme.amber; case "review": return Theme.violet; case "done": return Theme.green; default: return Theme.muted }
}

// MARK: - Отправки Авито (6.25) и возвраты (6.26)

struct ShipItem: Codable, Hashable {
    var article: String
    var name: String
    var qty: Int
    enum K: String, CodingKey { case article, name, qty }
    init(article: String, name: String, qty: Int) { self.article = article; self.name = name; self.qty = qty }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        article = c.flexString(.article) ?? ""; name = c.flexString(.name) ?? ""; qty = max(1, c.flexInt(.qty))
    }
    func encode(to e: Encoder) throws { var c = e.container(keyedBy: K.self); try c.encode(article, forKey: .article); try c.encode(name, forKey: .name); try c.encode(qty, forKey: .qty) }
}
struct ShipCan: Decodable, Hashable {
    let edit: Bool, cancel: Bool, pack: Bool, send: Bool, unpack: Bool
    let receive: Bool, unreceive: Bool, check: Bool, makeReturn: Bool, photo: Bool
    enum K: String, CodingKey { case edit, cancel, pack, send, unpack, receive, unreceive, check, photo; case makeReturn = "return" }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        edit = c.flexInt(.edit) == 1; cancel = c.flexInt(.cancel) == 1; pack = c.flexInt(.pack) == 1; send = c.flexInt(.send) == 1; unpack = c.flexInt(.unpack) == 1
        receive = c.flexInt(.receive) == 1; unreceive = c.flexInt(.unreceive) == 1; check = c.flexInt(.check) == 1
        makeReturn = c.flexInt(.makeReturn) == 1; photo = c.flexInt(.photo) == 1
    }
}
struct ShipPhoto: Decodable, Hashable, Identifiable {
    let id: String, by: String
    enum K: String, CodingKey { case id, by }
    init(from d: Decoder) throws { let c = try d.container(keyedBy: K.self); id = c.flexString(.id) ?? ""; by = c.flexString(.by) ?? "" }
    var path: String { "/api/shipments.php?action=photo&id=\(id)" }
}
struct Shipment: Decodable, Hashable, Identifiable {
    let id: String, kind: String, status: String, statusLabel: String
    let accountId: String, account: String, carrierId: String, carrier: String
    let track: String, comment: String, items: [ShipItem]
    let cost: String, pvz: String, pvzAddress: String, sourceId: String, returnId: String
    let createdBy: String, createdByName: String, createdAt: String
    let packedByName: String, packedAt: String, sentByName: String, sentAt: String
    let receivedByName: String, receivedAt: String, checkedByName: String, checkedAt: String
    let checkResult: String, checkComment: String
    let cancelledByName: String, cancelReason: String
    let photos: [ShipPhoto]
    let can: ShipCan?
    var isReturn: Bool { kind == "return" }
    enum K: String, CodingKey { case id, kind, status, statusLabel, accountId, account, carrierId, carrier, track, comment, items, cost, pvz, pvzAddress, sourceId, returnId,
        createdBy, createdByName, createdAt, packedByName, packedAt, sentByName, sentAt, receivedByName, receivedAt, checkedByName, checkedAt, checkResult, checkComment,
        cancelledByName, cancelReason, photos, can }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        func s(_ k: K) -> String { c.flexString(k) ?? "" }
        id = s(.id); kind = c.flexString(.kind) ?? "ship"; status = s(.status); statusLabel = s(.statusLabel)
        accountId = s(.accountId); account = s(.account); carrierId = s(.carrierId); carrier = s(.carrier); track = s(.track); comment = s(.comment)
        items = (try? c.decodeIfPresent([ShipItem].self, forKey: .items)) ?? []
        cost = (try? c.decodeIfPresent(String.self, forKey: .cost)) ?? ""
        pvz = s(.pvz); pvzAddress = s(.pvzAddress); sourceId = s(.sourceId); returnId = s(.returnId)
        createdBy = s(.createdBy); createdByName = s(.createdByName); createdAt = s(.createdAt)
        packedByName = s(.packedByName); packedAt = s(.packedAt); sentByName = s(.sentByName); sentAt = s(.sentAt)
        receivedByName = s(.receivedByName); receivedAt = s(.receivedAt); checkedByName = s(.checkedByName); checkedAt = s(.checkedAt)
        checkResult = s(.checkResult); checkComment = s(.checkComment)
        cancelledByName = s(.cancelledByName); cancelReason = s(.cancelReason)
        photos = (try? c.decodeIfPresent([ShipPhoto].self, forKey: .photos)) ?? []
        can = try? c.decodeIfPresent(ShipCan.self, forKey: .can)
    }
}
struct ShipmentsResponse: Decodable { let ok: Bool; let shipments: [Shipment]; let counts: [String: Int]?; let returnsOpen: Int? }
struct ShipmentResponse: Decodable { let ok: Bool; let shipment: Shipment }
struct ShipAccount: Decodable, Hashable, Identifiable {
    let id: String, name: String, active: Bool, users: [String]
    enum K: String, CodingKey { case id, name, active, users }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""; name = c.flexString(.name) ?? ""
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? true
        users = (try? c.decodeIfPresent([String].self, forKey: .users)) ?? []
    }
}
struct ShipCarrier: Decodable, Hashable, Identifiable {
    let id: String, name: String, active: Bool
    enum K: String, CodingKey { case id, name, active }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? ""; name = c.flexString(.name) ?? ""
        active = (try? c.decodeIfPresent(Bool.self, forKey: .active)) ?? true
    }
}
struct ShipOptions: Decodable {
    let ok: Bool
    let myAccounts: [ShipAccount]
    let accounts: [ShipAccount]
    let carriers: [ShipCarrier]
    let warehouse: [String]
    let isBoss: Bool
    let isWarehouse: Bool
    let roomId: String
}
struct ShipStatRow: Decodable, Hashable, Identifiable {
    let id: String, name: String
    let ships: Int, sent: Int, qty: Int, returns: Int, returnQty: Int, defects: Int, costCount: Int
    let cost: Double
    enum K: String, CodingKey { case id, name, ships, sent, qty, returns, returnQty, defects, cost, costCount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = c.flexString(.id) ?? UUID().uuidString; name = c.flexString(.name) ?? "Итого"
        ships = c.flexInt(.ships); sent = c.flexInt(.sent); qty = c.flexInt(.qty); returns = c.flexInt(.returns)
        returnQty = c.flexInt(.returnQty); defects = c.flexInt(.defects); costCount = c.flexInt(.costCount)
        cost = (try? c.decodeIfPresent(Double.self, forKey: .cost)) ?? Double(c.flexString(.cost) ?? "") ?? 0
    }
}
struct ShipStats: Decodable { let ok: Bool; let period: String; let shift: Int; let label: String; let accounts: [ShipStatRow]; let total: ShipStatRow }

func shipStatusColor(_ s: String) -> Color {
    switch s { case "new", "await": return Theme.amber; case "packed", "received": return Theme.blue; case "sent", "checked": return Theme.green; default: return Theme.red }
}
func shipStatusText(_ s: String, isReturn: Bool = false) -> String {
    switch s {
    case "new": return "🕐 Ждёт упаковки"
    case "packed": return "✅ Упакован"
    case "sent": return "🚚 Отправлено"
    case "await": return "🕐 Ждём возврат"
    case "received": return "📥 Получен"
    case "checked": return "✔️ Проверен"
    default: return isReturn ? "✖️ Отменён" : "✖️ Отменена"
    }
}
func shipRub(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "ru_RU"); f.maximumFractionDigits = 2
    return (f.string(from: NSNumber(value: v)) ?? String(v)) + " ₽"
}
