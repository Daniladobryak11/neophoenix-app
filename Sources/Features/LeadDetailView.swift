import SwiftUI

/// Карточка заявки: статус, комментарий, звонок.
struct LeadDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let leadId: String
    @State private var status = ""
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showOrder = false

    private var lead: Lead? { state.leads.first { $0.id == leadId } }

    var body: some View {
        NavigationStack {
            Form {
                if let l = lead {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(l.kindLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold); Spacer(); Text(dateLine(l.createdAt)).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                            Text(l.name.isEmpty ? "Без имени" : l.name).font(.system(size: 20, weight: .semibold))
                            if !l.phone.isEmpty { Text(l.phone).foregroundStyle(Theme.muted) }
                            if let s = l.source, !s.isEmpty { Tag(text: s) }
                        }
                        if !l.phone.isEmpty {
                            HStack(spacing: 8) {
                                Button { call(l.phone) } label: { Label("Позвонить", systemImage: "phone.fill") }.buttonStyle(SoftButtonStyle())
                                Button { whatsapp(l.phone) } label: { Text("WhatsApp") }.buttonStyle(SoftButtonStyle(tint: Theme.green))
                            }
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        }
                    }
                    if !(l.message ?? "").isEmpty || !(l.car ?? "").isEmpty || !(l.product ?? "").isEmpty {
                        Section("Что просит") {
                            if let m = l.message, !m.isEmpty { Text(m) }
                            if let c = l.car, !c.isEmpty { LabeledContent("Автомобиль", value: c) }
                            if let p = l.product, !p.isEmpty { LabeledContent("Товар", value: p) }
                        }
                    }
                    Section {
                        if let oid = l.orderId, !oid.isEmpty, let o = state.orders.first(where: { $0.id == oid }) {
                            Label("Заказ \(o.number) · \(o.status)", systemImage: "doc.text").foregroundStyle(Theme.green)
                        } else {
                            Button { showOrder = true } label: { Label("Создать заказ из заявки", systemImage: "cart.badge.plus") }
                                .buttonStyle(GoldButtonStyle())
                                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        }
                    }
                    Section("Статус") {
                        Picker("Статус", selection: $status) {
                            ForEach(leadStatuses) { Text($0.label).tag($0.id) }
                        }.pickerStyle(.segmented)
                        if let m = l.managerName, !m.isEmpty { LabeledContent("Ведёт", value: m) }
                    }
                    Section("Комментарий") {
                        TextField("Что сделали, о чём договорились", text: $comment, axis: .vertical).lineLimit(3...8)
                    }
                    if let error { Text(error).foregroundStyle(Theme.red) }
                } else {
                    Text("Заявка не найдена")
                }
            }
            .navigationTitle("Заявка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("Сохранить") } }
                        .disabled(busy || lead == nil)
                }
            }
            .onAppear { if let l = lead { status = l.status; comment = l.comment ?? "" } }
            .sheet(isPresented: $showOrder, onDismiss: { if let l = lead { status = l.status } }) { NewOrderView(lead: lead) }
        }
    }

    private func save() async {
        guard let l = lead else { return }
        busy = true; defer { busy = false }
        do { try await state.setLeadStatus(l, status, comment: comment); dismiss() }
        catch { self.error = error.localizedDescription }
    }
    private func call(_ phone: String) {
        if let u = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") { openURL(u) }
    }
    private func whatsapp(_ phone: String) {
        var d = phone.filter { $0.isNumber }
        if d.hasPrefix("8") && d.count == 11 { d = "7" + d.dropFirst() }
        if let u = URL(string: "https://wa.me/\(d)") { openURL(u) }
    }
}

/// Новая заявка, принятая сотрудником: Авито, звонок или мессенджер.
struct NewLeadView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var source = "Звонок"
    @State private var kind = "question"
    @State private var name = ""
    @State private var phone = ""
    @State private var link = ""
    @State private var message = ""
    @State private var car = ""
    @State private var product = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Откуда") {
                    Picker("Источник", selection: $source) { ForEach(leadSources, id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                    Picker("Тип", selection: $kind) { ForEach(leadKinds) { Text($0.label).tag($0.id) } }
                }
                Section("Клиент") {
                    TextField(source == "Авито" ? "Имя (как подписан на Авито)" : "Имя", text: $name)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                    if source != "Звонок" { TextField("Ссылка на переписку", text: $link).keyboardType(.URL).textInputAutocapitalization(.never) }
                }
                Section("Что нужно") {
                    TextField("Автомобиль", text: $car)
                    TextField("Товар", text: $product)
                    TextField("Комментарий", text: $message, axis: .vertical).lineLimit(2...6)
                }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Новая заявка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("Создать") } }.disabled(busy || name.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            try await state.createLead(["source": source, "kind": kind, "name": name, "phone": phone, "link": link, "message": message, "car": car, "product": product])
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
