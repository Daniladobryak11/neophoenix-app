import SwiftUI

struct OrdersView: View {
    @EnvironmentObject var state: AppState
    @State private var filter: Filter = .mine
    @State private var query = ""
    enum Filter: String, CaseIterable { case mine = "Мои", active = "Все активные", awaitingPay = "Ждут оплату", all = "Все" }

    private var list: [Order] {
        var l = state.orders
        switch filter {
        case .mine: l = l.filter { $0.isActive && ($0.manager == state.user?.id || ($0.manager ?? "").isEmpty) }
        case .active: l = l.filter { $0.isActive }
        case .awaitingPay: l = l.filter { $0.status == "Ожидает оплаты" || (($0.payment?.due ?? 0) > 0 && $0.isActive) }
        case .all: break
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            l = l.filter { o in
                [o.number, o.client, o.phone ?? "", o.delivery?.tracking ?? ""].contains { $0.lowercased().contains(q) }
            }
        }
        return l
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ShiftBanner()
                    stats
                    filters
                    if let e = state.ordersError, state.orders.isEmpty {
                        ErrorCard(text: e) { Task { await state.refreshOrders() } }
                    } else if list.isEmpty {
                        EmptyCard(icon: "doc.text", text: state.lastSync == nil ? "Загружаю заказы…" : "Здесь пока пусто")
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(list) { o in
                            NavigationLink(value: o.id) { OrderRow(order: o, mine: o.manager == state.user?.id) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
            .background(Theme.bg)
            .refreshable { async let a: Void = state.refreshOrders(); async let b: Void = state.refreshWork(); _ = await (a, b) }
            .searchable(text: $query, prompt: "Номер, клиент, телефон, трек")
            .navigationTitle("Заказы")
            .navigationDestination(for: String.self) { id in OrderDetailView(orderId: id) }
        }
    }

    private var stats: some View {
        let active = state.orders.filter { $0.isActive }
        return HStack(spacing: 8) {
            StatTile(value: "\(state.newOrders)", label: "новых", accent: true)
            StatTile(value: "\(active.count)", label: "в работе")
            StatTile(value: rub(active.reduce(0) { $0 + $1.total }).replacingOccurrences(of: "\u{00A0}₽", with: ""), label: "₽ активных")
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Button { withAnimation(.easeOut(duration: 0.2)) { filter = f } } label: {
                        Text(f.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 16).frame(height: 36)
                            .foregroundStyle(filter == f ? Theme.onGold : Theme.text)
                            .background(filter == f ? Theme.goldFill : Theme.card2, in: Capsule())
                    }
                }
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var accent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(accent ? Theme.gold : Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .card(padding: 12)
    }
}

struct OrderRow: View {
    let order: Order
    var mine = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(order.number).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                Pill(text: order.status, color: orderStatusColor(order.status))
                Spacer(minLength: 4)
                Text(ago(order.createdAt)).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(order.client).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(rub(order.total)).font(.system(size: 17, weight: .semibold))
            }
            HStack(spacing: 6) {
                if let s = order.source, !s.isEmpty { Tag(text: s) }
                if !order.deliveryLine.isEmpty { Text(order.deliveryLine).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1) }
                Spacer(minLength: 0)
                if (order.manager ?? "").isEmpty && order.isActive { Text("без менеджера").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.amber) }
            }
        }
        .card(padding: 14)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(mine && order.status == "Новый" ? Theme.gold.opacity(0.5) : .clear, lineWidth: 1.5))
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.gold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.gold.opacity(0.12), in: Capsule())
    }
}

struct EmptyCard: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Theme.gold)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

struct ErrorCard: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(Theme.red)
            Text(text).font(.system(size: 15)).multilineTextAlignment(.center)
            Button("Повторить", action: retry).buttonStyle(SoftButtonStyle())
        }
        .card()
    }
}
