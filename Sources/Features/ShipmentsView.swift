import SwiftUI

/// Отправки Авито: список с фильтрами, форма, карточка, настройки.
func shipDate(_ s: String) -> String {
    guard let d = parseISO(s) else { return s }
    return d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
}

enum ShipStore {
    static func options() async -> ShipOptions? {
        try? await API.shared.get("/api/shipments.php?action=options", as: ShipOptions.self)
    }
}

// MARK: - Подвал карточки в чате

struct ShipCardFooter: View {
    let message: ChatMessage
    let canMark: Bool
    let onMark: (String) -> Void
    private func t(_ s: String?) -> String {
        guard let d = parseSQLDate(s) else { return "" }
        return d.formatted(date: .omitted, time: .shortened)
    }
    var body: some View {
        let st = message.shipStatus ?? "new"
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(shipStatusText(st)).font(.system(size: 15, weight: .semibold)).foregroundStyle(shipStatusColor(st))
            if let p = message.shipPackedBy, !p.isEmpty { Text("Упаковал: \(p) · \(t(message.shipPackedAt))").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            if let p = message.shipSentBy, !p.isEmpty { Text("Отправил: \(p) · \(t(message.shipSentAt))").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            if st == "cancelled", let r = message.shipCancelReason, !r.isEmpty { Text("Причина: \(r)").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            if canMark && st == "new" {
                Button { onMark("packed") } label: { Label("Упакован", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(GoldButtonStyle())
            } else if canMark && st == "packed" {
                Button { onMark("sent") } label: { Label("Отправлено", systemImage: "truck.box.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(GoldButtonStyle())
                Button { onMark("new") } label: { Text("Снять «Упакован»").frame(maxWidth: .infinity) }
                    .buttonStyle(SoftButtonStyle())
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Список

struct ShipmentsView: View {
    @EnvironmentObject var state: AppState
    @State private var filter = "new"
    @State private var q = ""
    @State private var list: [Shipment] = []
    @State private var counts: [String: Int] = [:]
    @State private var loaded = false
    @State private var error: String?
    @State private var showNew = false
    @State private var showSettings = false
    @State private var opt: ShipOptions?

    private let filters: [(String, String)] = [("new", "Ждут упаковки"), ("packed", "Упакованы"), ("sent", "Отправлены"), ("cancelled", "Отменённые"), ("all", "Все")]

    var body: some View {
        NavigationStack {
            List {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.0) { f in
                            let n = f.0 == "all" ? counts.values.reduce(0, +) : (counts[f.0] ?? 0)
                            Button { filter = f.0 } label: {
                                Text(n > 0 ? "\(f.1) · \(n)" : f.1)
                                    .font(.system(size: 14, weight: .semibold))
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(filter == f.0 ? Theme.goldFill : Theme.card, in: Capsule())
                                    .foregroundStyle(filter == f.0 ? Theme.onGold : Theme.text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                if let e = error, list.isEmpty {
                    ErrorCard(text: e) { Task { await load() } }.listRowBackground(Color.clear)
                } else if list.isEmpty {
                    EmptyCard(icon: "shippingbox", text: loaded ? (q.isEmpty ? "Отправок нет" : "Ничего не найдено") : "Загружаю…").listRowBackground(Color.clear)
                }
                ForEach(list) { s in
                    NavigationLink(value: s.id) { ShipmentRow(s: s) }.listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .searchable(text: $q, prompt: "Трек, артикул, аккаунт")
            .refreshable { await load() }
            .task(id: filter + "|" + q) {
                if !q.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
                await load()
            }
            .task { opt = await ShipStore.options() }
            .navigationTitle("Отправки")
            .meButton()
            .navigationDestination(for: String.self) { id in ShipmentDetailView(shipId: id, onChange: { Task { await load() } }) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if opt?.isBoss == true { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Настройки отправок") }
                        Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Новая отправка")
                    }
                }
            }
            .sheet(isPresented: $showNew, onDismiss: { Task { await load() } }) { ShipmentFormView(editing: nil) }
            .sheet(isPresented: $showSettings, onDismiss: { Task { opt = await ShipStore.options() } }) { ShipSettingsView() }
        }
    }

    private func load() async {
        let qs = q.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        do {
            let r: ShipmentsResponse = try await API.shared.get("/api/shipments.php?action=list&status=\(filter)&q=\(qs)")
            list = r.shipments; counts = r.counts ?? [:]; error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct ShipmentRow: View {
    let s: Shipment
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("№\(s.id) · \(s.account)").font(.system(size: 16, weight: .semibold))
                Spacer()
                Pill(text: s.statusLabel.isEmpty ? shipStatusText(s.status) : s.statusLabel, color: shipStatusColor(s.status))
            }
            Text(s.items.map { "\($0.article) — \($0.qty) шт" }.joined(separator: ", "))
                .font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(2)
            Text("\(s.carrier) · трек \(s.track) · \(s.createdByName)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Карточка отправки

struct ShipmentDetailView: View {
    let shipId: String
    var onChange: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var s: Shipment?
    @State private var error: String?
    @State private var busy = false
    @State private var editing: Shipment?
    @State private var askCancel = false
    @State private var reason = ""

    var body: some View {
        List {
            if let s {
                Section {
                    HStack {
                        Text("Отправка №\(s.id)").font(.system(size: 20, weight: .bold))
                        Spacer()
                        Pill(text: shipStatusText(s.status), color: shipStatusColor(s.status))
                    }
                    row("Аккаунт Авито", s.account)
                    row("Транспортная компания", s.carrier)
                    HStack {
                        row("Трек-номер", s.track)
                        Button { UIPasteboard.general.string = s.track } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
                    }
                    if !s.comment.isEmpty { row("Комментарий", s.comment) }
                }
                Section("Товары") {
                    ForEach(Array(s.items.enumerated()), id: \.offset) { _, it in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.article).font(.system(size: 16, weight: .semibold))
                                if !it.name.isEmpty { Text(it.name).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                            }
                            Spacer()
                            Text("\(it.qty) шт").font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                Section("История") {
                    row("Создал", s.createdByName + " · " + shipDate(s.createdAt))
                    if !s.packedByName.isEmpty { row("Упаковал", s.packedByName + " · " + shipDate(s.packedAt)) }
                    if !s.sentByName.isEmpty { row("Отправил", s.sentByName + " · " + shipDate(s.sentAt)) }
                    if s.status == "cancelled" { row("Отменил", s.cancelledByName + (s.cancelReason.isEmpty ? "" : " · " + s.cancelReason)) }
                }
                if let c = s.can, c.pack || c.send || c.unpack || c.edit || c.cancel {
                    Section {
                        if c.pack { Button { Task { await mark("packed") } } label: { Label("Упакован", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity) }.buttonStyle(GoldButtonStyle()) }
                        if c.send { Button { Task { await mark("sent") } } label: { Label("Отправлено", systemImage: "truck.box.fill").frame(maxWidth: .infinity) }.buttonStyle(GoldButtonStyle()) }
                        if c.unpack { Button { Task { await mark("new") } } label: { Text("Снять «Упакован»").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle()) }
                        if c.edit { Button { editing = s } label: { Label("Изменить", systemImage: "pencil").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle()) }
                        if c.cancel { Button(role: .destructive) { askCancel = true } label: { Label("Отменить отправку", systemImage: "xmark.circle").frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle()) }
                    }
                    .listRowBackground(Color.clear)
                    .disabled(busy)
                }
            } else if let error {
                ErrorCard(text: error) { Task { await load() } }.listRowBackground(Color.clear)
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Отправка")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load(); onChange() } }) { e in ShipmentFormView(editing: e) }
        .alert("Отменить отправку?", isPresented: $askCancel) {
            TextField("Причина", text: $reason)
            Button("Отменить отправку", role: .destructive) { Task { await cancel() } }
            Button("Назад", role: .cancel) {}
        } message: { Text("Карточка в чате отметится как отменённая.") }
        .alert("Ошибка", isPresented: Binding(get: { error != nil && s != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 16)).textSelection(.enabled)
        }
    }
    private func load() async {
        do { let r: ShipmentResponse = try await API.shared.get("/api/shipments.php?action=get&id=\(shipId)"); s = r.shipment; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func mark(_ to: String) async {
        busy = true; defer { busy = false }
        do {
            let r: ShipmentResponse = try await API.shared.post("/api/shipments.php?action=mark", ["id": Int(shipId) ?? 0, "to": to])
            s = r.shipment; onChange()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { self.error = error.localizedDescription }
    }
    private func cancel() async {
        busy = true; defer { busy = false }
        do {
            let r: ShipmentResponse = try await API.shared.post("/api/shipments.php?action=cancel", ["id": Int(shipId) ?? 0, "reason": reason])
            s = r.shipment; onChange()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Форма создания / изменения

struct ShipmentFormView: View {
    let editing: Shipment?
    @Environment(\.dismiss) private var dismiss
    @State private var opt: ShipOptions?
    @State private var accountId = ""
    @State private var carrierId = ""
    @State private var items: [ShipItem] = [ShipItem(article: "", name: "", qty: 1)]
    @State private var track = ""
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?
    @State private var products: [Product] = []
    @State private var pickFor: Int?

    var body: some View {
        NavigationStack {
            Form {
                if let opt, opt.myAccounts.isEmpty && editing == nil {
                    Section {
                        Text(opt.isBoss ? "Сначала добавьте аккаунт Авито: Отправки → ⚙︎ Настройки." : "За вами не закреплён ни один аккаунт Авито — обратитесь к администратору.")
                            .foregroundStyle(Theme.red)
                    }
                }
                Section("Аккаунт Авито") {
                    Picker("Аккаунт", selection: $accountId) {
                        ForEach(opt?.myAccounts ?? []) { a in Text(a.name).tag(a.id) }
                    }
                }
                Section {
                    ForEach(items.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                TextField("Артикул", text: Binding(get: { items[i].article }, set: { v in
                                    items[i].article = v
                                    items[i].name = products.first { ($0.article ?? "").caseInsensitiveCompare(v.trimmingCharacters(in: .whitespaces)) == .orderedSame }?.name ?? ""
                                }))
                                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                Button { pickFor = i } label: { Image(systemName: "list.bullet.rectangle") }.buttonStyle(.borderless)
                                    .accessibilityLabel("Из каталога")
                            }
                            if !items[i].name.isEmpty { Text(items[i].name).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                            Stepper(value: $items[i].qty, in: 1...10000) { Text("Количество: \(items[i].qty) шт") }
                        }
                    }
                    .onDelete { idx in if items.count > 1 { items.remove(atOffsets: idx) } }
                    Button { items.append(ShipItem(article: "", name: "", qty: 1)) } label: { Label("Ещё товар", systemImage: "plus.circle") }
                } header: { Text("Товары") } footer: { Text("Впишите артикул вручную или выберите из каталога. Цена не указывается.") }
                Section("Транспортная компания") {
                    Picker("Компания", selection: $carrierId) {
                        ForEach((opt?.carriers ?? []).filter { $0.active || $0.id == carrierId }) { c in Text(c.name).tag(c.id) }
                    }
                }
                Section("Трек-номер") {
                    TextField("Обязательно", text: $track).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                Section("Комментарий") {
                    TextField("Необязательно", text: $comment, axis: .vertical).lineLimit(2...6)
                }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(editing == nil ? "Новая отправка" : "Отправка №\(editing!.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Создать" : "Сохранить") { Task { await save() } }.disabled(busy).fontWeight(.semibold)
                }
            }
            .sheet(item: Binding(get: { pickFor.map { IdBox(id: String($0)) } }, set: { pickFor = $0.flatMap { Int($0.id) } })) { b in
                ShipCatalogPicker(products: products) { p in
                    if let i = Int(b.id), i < items.count { items[i].article = p.article ?? ""; items[i].name = p.name }
                }
            }
            .task { await setup() }
        }
    }

    private func setup() async {
        opt = await ShipStore.options()
        if let e = editing {
            accountId = e.accountId; carrierId = e.carrierId; track = e.track; comment = e.comment
            items = e.items.isEmpty ? [ShipItem(article: "", name: "", qty: 1)] : e.items
        } else {
            if accountId.isEmpty { accountId = opt?.myAccounts.first?.id ?? "" }
            if carrierId.isEmpty { carrierId = opt?.carriers.first { $0.active }?.id ?? "" }
        }
        if let r = try? await API.shared.get("/api/catalog.php?action=bootstrap", as: CatalogResponse.self) {
            products = (r.data?.products ?? []).filter { !($0.article ?? "").isEmpty }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let list = items.filter { !$0.article.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ["article": $0.article.trimmingCharacters(in: .whitespaces), "name": $0.name, "qty": $0.qty] as [String: Any] }
        var body: [String: Any] = ["accountId": Int(accountId) ?? 0, "carrierId": Int(carrierId) ?? 0, "track": track, "comment": comment, "items": list]
        if let e = editing { body["id"] = Int(e.id) ?? 0 }
        do {
            _ = try await API.shared.post("/api/shipments.php?action=" + (editing == nil ? "create" : "update"), body, as: ShipmentResponse.self)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Каталог без цен — только название, артикул и наличие.
struct ShipCatalogPicker: View {
    let products: [Product]
    let onPick: (Product) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    private var list: [Product] {
        let s = q.lowercased().trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? products : products.filter { $0.name.lowercased().contains(s) || ($0.article ?? "").lowercased().contains(s) }
    }
    var body: some View {
        NavigationStack {
            List(list) { p in
                Button { onPick(p); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.article ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(p.name).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
            }
            .overlay { if products.isEmpty { ProgressView() } }
            .searchable(text: $q, prompt: "Артикул или название")
            .navigationTitle("Из каталога")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

// MARK: - Настройки (владелец/админ)

struct ShipSettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var opt: ShipOptions?
    @State private var error: String?
    @State private var editAccount: ShipAccount?
    @State private var newAccount = false
    @State private var carrierEdit: ShipCarrier?
    @State private var carrierName = ""
    @State private var newCarrier = false

    private var staff: [StaffProfile] { state.staff.filter { ["owner", "admin", "manager"].contains($0.role) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(opt?.accounts ?? []) { a in
                        Button { editAccount = a } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).foregroundStyle(a.active ? Theme.text : Theme.muted)
                                Text(a.users.isEmpty ? "никто не закреплён" : a.users.compactMap { id in state.profile(id)?.name }.joined(separator: ", "))
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                        }
                    }
                    Button { newAccount = true } label: { Label("Добавить аккаунт", systemImage: "plus.circle") }
                } header: { Text("Аккаунты Авито") } footer: { Text("Сотрудник видит в форме только закреплённые за ним аккаунты.") }

                Section {
                    ForEach(opt?.carriers ?? []) { c in
                        HStack {
                            Button { carrierEdit = c; carrierName = c.name } label: { Text(c.name).foregroundStyle(c.active ? Theme.text : Theme.muted) }
                            Spacer()
                            Toggle("", isOn: Binding(get: { c.active }, set: { v in Task { await saveCarrier(id: c.id, name: c.name, active: v) } })).labelsHidden()
                        }
                    }
                    Button { carrierName = ""; newCarrier = true } label: { Label("Добавить компанию", systemImage: "plus.circle") }
                } header: { Text("Транспортные компании") } footer: { Text("Выключенные не показываются в форме.") }

                Section {
                    ForEach(staff) { p in
                        Toggle(isOn: Binding(get: { opt?.warehouse.contains(p.id) ?? false }, set: { v in Task { await setWarehouse(p.id, v) } })) {
                            HStack(spacing: 10) { Avatar(userId: p.id, name: p.name, size: 30); Text(p.name) }
                        }
                    }
                } header: { Text("Работают на складе") } footer: { Text("Они получают уведомления о новых отправках и ставят отметки «Упакован» и «Отправлено». Владелец и администраторы могут ставить отметки всегда.") }

                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("Настройки отправок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task { opt = await ShipStore.options(); if state.staff.isEmpty { await state.refreshStaff() } }
            .sheet(item: $editAccount) { a in AccountEditView(account: a, staff: staff) { o in opt = o } }
            .sheet(isPresented: $newAccount) { AccountEditView(account: nil, staff: staff) { o in opt = o } }
            .alert("Транспортная компания", isPresented: Binding(get: { carrierEdit != nil || newCarrier }, set: { if !$0 { carrierEdit = nil; newCarrier = false } })) {
                TextField("Название", text: $carrierName)
                Button("Сохранить") { let c = carrierEdit; Task { await saveCarrier(id: c?.id, name: carrierName, active: c?.active ?? true) } }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func saveCarrier(id: String?, name: String, active: Bool) async {
        var b: [String: Any] = ["name": name, "active": active]
        if let id { b["id"] = Int(id) ?? 0 }
        do { opt = try await API.shared.post("/api/shipments.php?action=carrier-save", b, as: ShipOptions.self); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func setWarehouse(_ uid: String, _ on: Bool) async {
        do { opt = try await API.shared.post("/api/shipments.php?action=warehouse", ["userId": Int(uid) ?? 0, "on": on], as: ShipOptions.self); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct AccountEditView: View {
    let account: ShipAccount?
    let staff: [StaffProfile]
    let onSaved: (ShipOptions) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var active = true
    @State private var users: Set<String> = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") { TextField("Например, Нео Феникс Москва", text: $name) }
                Section { Toggle("Аккаунт активен", isOn: $active) }
                Section {
                    ForEach(staff) { p in
                        Button {
                            if users.contains(p.id) { users.remove(p.id) } else { users.insert(p.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Avatar(userId: p.id, name: p.name, size: 30)
                                Text(p.name).foregroundStyle(Theme.text)
                                Spacer()
                                if users.contains(p.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold) }
                                else { Image(systemName: "circle").foregroundStyle(Theme.muted) }
                            }
                        }
                    }
                } header: { Text("Сотрудники") } footer: { Text("Кто может создавать отправки от этого аккаунта.") }
                if let error { Section { Text(error).foregroundStyle(Theme.red) } }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(account == nil ? "Новый аккаунт" : "Аккаунт Авито")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { Task { await save() } }.disabled(busy).fontWeight(.semibold) }
            }
            .onAppear { if let a = account { name = a.name; active = a.active; users = Set(a.users) } }
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        var b: [String: Any] = ["name": name, "active": active, "users": users.compactMap { Int($0) }]
        if let a = account { b["id"] = Int(a.id) ?? 0 }
        do { let o: ShipOptions = try await API.shared.post("/api/shipments.php?action=account-save", b); onSaved(o); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
