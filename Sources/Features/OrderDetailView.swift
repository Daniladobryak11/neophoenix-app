import SwiftUI

struct OrderDetailView: View {
    @EnvironmentObject var state: AppState
    let orderId: String
    @State private var busy = false
    @State private var error: String?
    @State private var showStatuses = false
    @State private var pickManager = false
    @State private var newTask = false
    @Environment(\.openURL) private var openURL

    private var order: Order? { state.orders.first { $0.id == orderId } }

    var body: some View {
        Group {
            if let o = order { content(o) } else { EmptyCard(icon: "doc.text", text: "Заказ не найден") }
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private func content(_ o: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(o.number).font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        Pill(text: o.status, color: orderStatusColor(o.status))
                    }
                    Text(([dateLine(o.createdAt), o.source].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · "))
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 4)

                ResponsibleRow(userId: o.manager, name: o.managerName, canChange: state.isBoss) { pickManager = true }
                    .card(padding: 14)
                clientCard(o)
                tasksCard(o)
                itemsCard(o)
                deliveryCard(o)
                if let c = o.comment, !c.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle("Комментарий")
                        Text(c).font(.system(size: 15))
                    }.card()
                }
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 16)
        }
        .refreshable { await state.refreshOrders() }
        .safeAreaInset(edge: .bottom) { actionBar(o) }
        .sheet(isPresented: $pickManager) {
            StaffPicker(title: "Ответственный за заказ", selected: o.manager, allowNone: true) { id in
                Task { busy = true; defer { busy = false }; do { try await state.updateOrder(o, manager: id); haptic() } catch { self.error = error.localizedDescription } }
            }
        }
        .sheet(isPresented: $newTask) { NewTaskView(orderId: o.id, presetTitle: "По заказу \(o.number): ") }
        .confirmationDialog("Статус заказа", isPresented: $showStatuses, titleVisibility: .visible) {
            ForEach(orderStatuses.filter { $0 != o.status }, id: \.self) { s in
                Button(s, role: s == "Отменён" ? .destructive : nil) { Task { await change(o, s) } }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func clientCard(_ o: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(initials(o.client)).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.gold)
                    .frame(width: 44, height: 44).background(Theme.gold.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.client).font(.system(size: 17, weight: .semibold))
                    if let p = o.phone, !p.isEmpty { Text(p).font(.system(size: 14)).foregroundStyle(Theme.muted) }
                }
            }
            if let p = o.phone, !p.isEmpty {
                HStack(spacing: 8) {
                    Button { call(p) } label: { Label("Звонок", systemImage: "phone.fill") }.buttonStyle(SoftButtonStyle())
                    Button { whatsapp(p) } label: { Text("WhatsApp") }.buttonStyle(SoftButtonStyle(tint: Theme.green))
                }
            }
            if let v = o.vehicle, !v.isEmpty {
                Label(v, systemImage: "car.fill").font(.system(size: 14)).foregroundStyle(Theme.green)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }.card()
    }

    private func tasksCard(_ o: Order) -> some View {
        let list = state.tasks.filter { $0.orderId == o.id && $0.isOpen }
        return VStack(alignment: .leading, spacing: 8) {
            HStack { SectionTitle("Задачи по заказу"); Spacer(); Button { newTask = true } label: { Label("Задача", systemImage: "plus") }.font(.system(size: 14, weight: .semibold)) }
            if list.isEmpty { Text("Открытых задач нет").font(.system(size: 14)).foregroundStyle(Theme.muted) }
            ForEach(list) { t in
                HStack(spacing: 8) {
                    Circle().fill(taskStatusColor(t.status)).frame(width: 8, height: 8)
                    Text(t.title).font(.system(size: 14)).lineLimit(1)
                    Spacer()
                    Avatar(userId: t.responsibleId, name: t.responsibleName, size: 22)
                }
            }
        }.card()
    }

    private func itemsCard(_ o: Order) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Товары")
            ForEach(o.items, id: \.stableId) { it in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.name).font(.system(size: 15))
                        Text("\(Int(it.qty)) × \(rub(it.price))" + ((it.article ?? "").isEmpty ? "" : " · арт. \(it.article!)"))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(rub(it.price * it.qty)).font(.system(size: 15, weight: .semibold))
                }
            }
            Divider().overlay(Theme.line)
            HStack { Text("Итого").font(.system(size: 16, weight: .semibold)); Spacer(); Text(rub(o.total)).font(.system(size: 18, weight: .bold)) }
            if let p = o.payment {
                HStack {
                    Text(p.due > 0 ? "Осталось оплатить" : "Оплачено").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(p.due > 0 ? rub(p.due) : rub(p.paid) + " ✓").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.due > 0 ? Theme.amber : Theme.green)
                }.font(.system(size: 15))
            }
        }.card()
    }

    private func deliveryCard(_ o: Order) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Получение")
            Text(o.delivery?.carrier?.isEmpty == false ? o.delivery!.carrier! : "Не выбрано").font(.system(size: 16, weight: .semibold))
            if let a = o.delivery?.address, !a.isEmpty { Text(a).font(.system(size: 14)).foregroundStyle(Theme.muted) }
            if let t = o.delivery?.tracking, !t.isEmpty {
                HStack { Text("Трек: \(t)").font(.system(size: 14)); Spacer()
                    if let u = o.delivery?.trackingUrl, let url = URL(string: u), !u.isEmpty { Button("Отследить") { openURL(url) }.font(.system(size: 14, weight: .semibold)) }
                }
            }
            if let m = o.managerName, !m.isEmpty { Text("Ведёт: \(m)").font(.system(size: 13)).foregroundStyle(Theme.muted) }
        }.card()
    }

    private func actionBar(_ o: Order) -> some View {
        HStack(spacing: 10) {
            Button { showStatuses = true } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)) }
                .buttonStyle(SoftButtonStyle()).frame(width: 56)
            if (o.manager ?? "").isEmpty && state.user?.role == "manager" && o.isActive {
                Button { Task { await take(o) } } label: { busyLabel("Взять в работу") }.buttonStyle(GoldButtonStyle())
            } else if let next = nextStatus(for: o) {
                Button { Task { await change(o, next) } } label: { busyLabel(next) }.buttonStyle(GoldButtonStyle())
            } else {
                Button { showStatuses = true } label: { Text("Изменить статус") }.buttonStyle(SoftButtonStyle())
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .disabled(busy)
    }

    @ViewBuilder private func busyLabel(_ t: String) -> some View {
        if busy { ProgressView().tint(Theme.onGold) } else { Text(t) }
    }

    private func take(_ o: Order) async {
        busy = true; defer { busy = false }
        do { try await state.takeOrder(o); haptic() } catch { self.error = error.localizedDescription }
    }
    private func change(_ o: Order, _ s: String) async {
        busy = true; defer { busy = false }
        do { try await state.setStatus(o, s); haptic() } catch { self.error = error.localizedDescription }
    }
    private func haptic() { UINotificationFeedbackGenerator().notificationOccurred(.success) }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let u = URL(string: "tel:\(digits)") { openURL(u) }
    }
    private func whatsapp(_ phone: String) {
        var d = phone.filter { $0.isNumber }
        if d.hasPrefix("8") && d.count == 11 { d = "7" + d.dropFirst() }
        if let u = URL(string: "https://wa.me/\(d)") { openURL(u) }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted)
    }
}

func initials(_ name: String) -> String {
    name.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()
}

func dateLine(_ iso: String) -> String {
    guard let d = parseISO(iso) else { return "" }
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM в HH:mm"
    return f.string(from: d)
}
