import SwiftUI

/// Мягкая палитра приложения: тёплый тёмный фон, песочное золото, без жёстких рамок.
/// Светлая тема — по настройке iPhone или вручную (раздел «Я»).
enum Theme {
    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    static let bg = dynamic(light: hex(0xF4F3F0), dark: hex(0x131418))
    static let card = dynamic(light: hex(0xFFFFFF), dark: hex(0x1C1E23))
    static let card2 = dynamic(light: hex(0xEFEEEA), dark: hex(0x24262B))
    static let text = dynamic(light: hex(0x15171B), dark: hex(0xECECEE))
    static let muted = dynamic(light: hex(0x6B6F78), dark: hex(0x9EA3AB))
    static let line = dynamic(light: hex(0x000000, 0.07), dark: hex(0xFFFFFF, 0.06))
    static let gold = dynamic(light: hex(0xB88D28), dark: hex(0xE9CF8A))
    static let goldFill = dynamic(light: hex(0xE2BE63), dark: hex(0xE9CF8A))
    static let onGold = Color(hex(0x2A2210))
    static let green = dynamic(light: hex(0x1D7F45), dark: hex(0x7FD6A0))
    static let red = dynamic(light: hex(0xCF2F2F), dark: hex(0xFF9A9E))
    static let blue = dynamic(light: hex(0x2463C9), dark: hex(0x9CC8F0))
    static let violet = dynamic(light: hex(0x5B33B8), dark: hex(0xC3A9F5))
    static let amber = dynamic(light: hex(0x9A4F08), dark: hex(0xF3D27A))

    static let radius: CGFloat = 22
}

/// Цвет статуса заказа — как в CRM.
func orderStatusColor(_ s: String) -> Color {
    switch s {
    case "Новый": return Theme.blue
    case "Ожидает оплаты": return Theme.amber
    case "Оплачен", "Готов к выдаче", "Выполнен": return Theme.green
    case "Отправлен", "Собран": return Theme.violet
    case "Отменён", "Возврат": return Theme.red
    default: return Theme.gold
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}
extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.onGold)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                LinearGradient(colors: [Color(red: 0.93, green: 0.84, blue: 0.58), Color(red: 0.89, green: 0.75, blue: 0.39)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.89, green: 0.75, blue: 0.39).opacity(0.25), radius: 10, y: 5)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Сумма в рублях: «5 300 ₽».
func rub(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "\u{00A0}"
    f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return (f.string(from: NSNumber(value: v)) ?? "\(Int(v))") + "\u{00A0}₽"
}

/// «12 мин», «3 ч», «вчера», «15 ноя».
func ago(_ iso: String) -> String {
    guard let d = parseISO(iso) else { return "" }
    let s = Date().timeIntervalSince(d)
    if s < 60 { return "сейчас" }
    if s < 3600 { return "\(Int(s / 60)) мин" }
    if Calendar.current.isDateInToday(d) { return "\(Int(s / 3600)) ч" }
    if Calendar.current.isDateInYesterday(d) { return "вчера" }
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMM"
    return f.string(from: d)
}

func parseISO(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s)
}
