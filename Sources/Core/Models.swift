import Foundation

/// Числа с сервера иногда приходят строкой, иногда числом — читаем оба варианта.
@propertyWrapper
struct FlexDouble: Decodable, Hashable {
    var wrappedValue: Double
    init(wrappedValue: Double) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { wrappedValue = d }
        else if let s = try? c.decode(String.self), let d = Double(s) { wrappedValue = d }
        else { wrappedValue = 0 }
    }
}

struct User: Decodable, Hashable {
    let id: String
    let name: String
    let email: String
    let phone: String?
    let role: String
    var roleLabel: String {
        switch role { case "owner": return "Владелец"; case "admin": return "Администратор"; default: return "Менеджер" }
    }
}

struct LoginResponse: Decodable { let ok: Bool; let token: String; let user: User }
struct MeResponse: Decodable { let ok: Bool; let user: User }
struct OkResponse: Decodable { let ok: Bool }

struct OrderItem: Decodable, Hashable, Identifiable {
    let id: String?
    let article: String?
    let name: String
    @FlexDouble var price: Double
    @FlexDouble var qty: Double
    var stableId: String { (id ?? "") + name }
}
extension OrderItem { var identity: String { stableId } }

struct Delivery: Decodable, Hashable {
    let carrier: String?
    let recipient: String?
    let phone: String?
    let address: String?
    let tracking: String?
    let trackingUrl: String?
}

struct Payment: Decodable, Hashable {
    @FlexDouble var paid: Double
    @FlexDouble var due: Double
    let online: Bool?
    let payUrl: String?
}

struct Order: Decodable, Hashable, Identifiable {
    let id: String
    let number: String
    let client: String
    let phone: String?
    let email: String?
    let items: [OrderItem]
    @FlexDouble var total: Double
    let status: String
    let manager: String?
    let managerName: String?
    let comment: String?
    let createdAt: String
    let delivery: Delivery?
    let source: String?
    let payment: Payment?
    let payAtCheckout: Bool?
    let vehicle: String?

    var isActive: Bool { !["Выполнен", "Отменён", "Возврат"].contains(status) }
    var deliveryLine: String {
        var parts: [String] = []
        if let c = delivery?.carrier, !c.isEmpty { parts.append(c) }
        if let t = delivery?.tracking, !t.isEmpty { parts.append("трек \(t)") }
        else if let a = delivery?.address, !a.isEmpty, delivery?.carrier != "Самовывоз" { parts.append(a) }
        if payAtCheckout == true { parts.append("онлайн-оплата") }
        return parts.joined(separator: " · ")
    }
}
struct OrdersResponse: Decodable { let ok: Bool; let orders: [Order] }

struct Lead: Decodable, Hashable, Identifiable {
    let id: String
    let kind: String
    let kindLabel: String
    let name: String
    let phone: String
    let message: String?
    let car: String?
    let product: String?
    let status: String
    let manager: String?
    let managerName: String?
    let comment: String?
    let source: String?
    let orderId: String?
    let createdAt: String

    var statusLabel: String {
        switch status { case "new": return "Новая"; case "work": return "В работе"; case "done": return "Обработана"; default: return "Спам" }
    }
    var details: String {
        [message, car, product].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
struct LeadsResponse: Decodable { let ok: Bool; let leads: [Lead] }

/// Статусы заказа в порядке работы — как в CRM.
let orderStatuses = ["Новый", "В работе", "Подтверждён", "Ожидает оплаты", "Оплачен", "Собран", "Отправлен", "Готов к выдаче", "Выполнен", "Отменён", "Возврат"]

/// Следующий шаг для большой кнопки внизу карточки заказа.
func nextStatus(for o: Order) -> String? {
    let pickup = o.delivery?.carrier == "Самовывоз"
    switch o.status {
    case "Новый": return "В работе"
    case "В работе": return "Подтверждён"
    case "Подтверждён": return "Ожидает оплаты"
    case "Оплачен": return "Собран"
    case "Собран": return pickup ? "Готов к выдаче" : "Отправлен"
    case "Отправлен", "Готов к выдаче": return "Выполнен"
    default: return nil
    }
}
