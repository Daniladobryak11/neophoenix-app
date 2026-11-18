import SwiftUI
import PhotosUI

/// Отправки Авито и возвраты: список с фильтрами, форма, карточка, фото, статистика, настройки.
func shipDate(_ s: String) -> String {
    guard let d = parseISO(s) else { return s }
    return d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
}

enum ShipStore {
    static func options() async -> ShipOptions? {
        try? await API.shared.get("/api/shipments.php?action=options", as: ShipOptions.self)
    }
    /// Загрузка фото по одному; возвращает свежую запись.
    static func upload(_ images: [UIImage], to sid: String) async throws -> Shipment? {
        var last: Shipment?
        for img in images {
            let data = shrink(img).jpegData(compressionQuality: 0.8) ?? Data()
            let r: ShipmentResponse = try await API.shared.upload("/api/shipments.php?action=photo-upload", fields: ["shipmentId": sid], fileField: "file", fileName: "photo.jpg", mime: "image/jpeg", data: data)
            last = r.shipment
        }
        return last
    }
    static func shrink(_ img: UIImage) -> UIImage {
        let maxSide: CGFloat = 2000
        let w = img.size.width, h = img.size.height
        guard max(w, h) > maxSide else { return img }
        let k = maxSide / max(w, h)
        let size = CGSize(width: w * k, height: h * k)
        return UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
    static func images(from items: [PhotosPickerItem]) async -> [UIImage] {
        var out: [UIImage] = []
        for it in items { if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { out.append(img) } }
        return out
    }
}

// MARK: - Подвал карточки в чате

struct ShipCardFooter: View {
    let message: ChatMessage
    let canMark: Bool
    let onMark: (String) -> Void
    private var isReturn: Bool { message.shipKind == "return" }
    private func t(_ s: String?) -> String {
        guard let d = parseSQLDate(s) else { return "" }
        return d.formatted(date: .omitted, time: .shortened)
    }
    private var statusLine: String {
        let st = message.shipStatus ?? "new"
        var s = shipStatusText(st, isReturn: isReturn)
        if isReturn && st == "checked" { s += message.shipCheckResult == "defect" ? " — брак" : " — целый" }
        return s
    }
    var body: some View {
        let st = message.shipStatus ?? "new"
        VStack(alignment: .leading, spacing: 6) {
            if !message.shipPhotos.isEmpty { photos }
            Divider()
            Text(statusLine).font(.system(size: 15, weight: .semibold)).foregroundStyle(shipStatusColor(st))
            history
            buttons(st)
        }
        .padding(.top, 2)
    }
    private var photos: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.shipPhotos, id: \.self) { id in
                    Button { onMark("open") } label: {
                        AuthImage(path: "/api/shipments.php?action=photo&id=\(id)")
                            .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    @ViewBuilder private var history: some View {
        if let p = message.shipPackedBy, !p.isEmpty { small("Упаковал: \(p) · \(t(message.shipPackedAt))") }
        if let p = message.shipSentBy, !p.isEmpty { small("Отправил: \(p) · \(t(message.shipSentAt))") }
        if let p = message.shipReceivedBy, !p.isEmpty { small("Получил: \(p) · \(t(message.shipReceivedAt))") }
        if let p = message.shipCheckedBy, !p.isEmpty { small("Проверил: \(p) · \(t(message.shipCheckedAt))" + ((message.shipCheckComment ?? "").isEmpty ? "" : " · " + (message.shipCheckComment ?? ""))) }
        if message.shipStatus == "cancelled", let r = message.shipCancelReason, !r.isEmpty { small("Причина: \(r)") }
    }
    private func small(_ s: String) -> some View { Text(s).font(.system(size: 12)).foregroundStyle(Theme.muted) }
    @ViewBuilder private func buttons(_ st: String) -> some View {
        if canMark && st == "new" { gold("Упакован", "checkmark.seal.fill", "packed") }
        else if canMark && st == "packed" { gold("Отправлено", "truck.box.fill", "sent"); soft("Снять «Упакован»", "new") }
        else if canMark && st == "await" { gold("Получен", "tray.and.arrow.down.fill", "received") }
        else if canMark && st == "received" { gold("Проверен", "checkmark.circle.fill", "checked"); soft("Снять «Получен»", "await") }
        soft("Открыть", "open")
    }
    private func gold(_ t: String, _ icon: String, _ to: String) -> some View {
        Button { onMark(to) } label: { Label(t, systemImage: icon).frame(maxWidth: .infinity) }.buttonStyle(GoldButtonStyle())
    }
    private func soft(_ t: String, _ to: String) -> some View {
        Button { onMark(to) } label: { Text(t).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle())
    }
}

// MARK: - Раздел «Отправки»

struct ShipmentsView: View {
    @EnvironmentObject var state: AppState
    @State private var section = "ship"
    @State private var filter = "new"
    @State private var q = ""
    @State private var list: [Shipment] = []
    @State private var counts: [String: Int] = [:]
    @State private var returnsOpen = 0
    @State private var loaded = false
    @State private var error: String?
    @State private var showNew = false
    @State private var showSettings = false
    @State private var opt: ShipOptions?

    private var filters: [(String, String)] {
        section == "return"
            ? [("open", "В работе"), ("await", "Ждём"), ("received", "Получены"), ("checked", "Проверены"), ("cancelled", "Отменённые"), ("all", "Все")]
            : [("new", "Ждут упаковки"), ("packed", "Упакованы"), ("sent", "Отправлены"), ("cancelled", "Отменённые"), ("all", "Все")]
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.bg)
                .navigationTitle("Отправки")
                .meButton()
                .navigationDestination(for: String.self) { id in ShipmentDetailView(shipId: id, onChange: { Task { await load() } }) }
                .toolbar { toolbar }
                .sheet(isPresented: $showNew, onDismiss: { Task { await load() } }) { ShipmentFormView(editing: nil, kind: section == "return" ? "return" : "ship") }
                .sheet(isPresented: $showSettings, onDismiss: { Task { opt = await ShipStore.options() } }) { ShipSettingsView() }
                .task { opt = await ShipStore.options() }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 14) {
                if opt?.isBoss == true { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Настройки отправок") }
                if section != "stats" { Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel(section == "return" ? "Новый возврат" : "Новая отправка") }
            }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            Picker("Раздел", selection: $section) {
                Text("Отправки").tag("ship")
                Text(returnsOpen > 0 ? "Возвраты · \(returnsOpen)" : "Возвраты").tag("return")
                Text("Статистика").tag("stats")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .onChange(of: section) { v in filter = v == "return" ? "open" : "new"; list = []; loaded = false }
            if section == "stats" { ShipStatsView() } else { listView }
        }
    }

    private var listView: some View {
        List {
            chips.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if let e = error, list.isEmpty {
                ErrorCard(text: e) { Task { await load() } }.listRowBackground(Color.clear)
            } else if list.isEmpty {
                EmptyCard(icon: section == "return" ? "arrow.uturn.backward" : "shippingbox", text: emptyText).listRowBackground(Color.clear)
            }
            ForEach(list) { s in
                NavigationLink(value: s.id) { ShipmentRow(s: s) }.listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $q, prompt: section == "return" ? "Номер, трек, артикул, ПВЗ" : "Номер, трек, артикул, аккаунт")
        .refreshable { await load() }
        .task(id: section + "|" + filter + "|" + q) {
            if !q.isEmpty { try? await Task.sleep(nanoseconds: 350_000_000) }
            await load()
        }
    }

    private var emptyText: String {
        if !loaded { return "Загружаю…" }
        if !q.isEmpty { return "Ничего не найдено" }
        return section == "return" ? "Возвратов нет. Возврат можно создать кнопкой «+» или из отправленной посылки — «Возврат» в её карточке." : "Отправок нет"
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.0) { f in chip(f.0, f.1) }
            }
            .padding(.vertical, 2).padding(.horizontal, 16)
        }
    }

    private func count(_ key: String) -> Int {
        switch key {
        case "all": return counts.values.reduce(0, +)
        case "open": return (counts["await"] ?? 0) + (counts["received"] ?? 0)
        default: return counts[key] ?? 0
        }
    }

    private func chip(_ key: String, _ title: String) -> some View {
        let n = count(key)
        let on = filter == key
        return Button { filter = key } label: {
            Text(n > 0 ? "\(title) · \(n)" : title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Theme.goldFill : Theme.card, in: Capsule())
                .foregroundStyle(on ? Theme.onGold : Theme.text)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard section != "stats" else { return }
        let qs = q.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        do {
            let r: ShipmentsResponse = try await API.shared.get("/api/shipments.php?action=list&kind=\(section)&status=\(filter)&q=\(qs)")
            list = r.shipments; counts = r.counts ?? [:]; returnsOpen = r.returnsOpen ?? 0; error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

struct ShipmentRow: View {
    let s: Shipment
    private var meta: String {
        var parts: [String] = []
        if !s.carrier.isEmpty { parts.append(s.carrier) }
        parts.append("трек " + s.track)
        if !s.pvz.isEmpty { parts.append(s.pvz) }
        if let c = Double(s.cost) { parts.append(shipRub(c)) }
        parts.append(s.createdByName)
        return parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((s.isReturn ? "↩️ " : "") + "№\(s.id) · \(s.account)").font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Pill(text: shipStatusText(s.status, isReturn: s.isReturn) + (s.checkResult == "defect" ? " · брак" : ""), color: shipStatusColor(s.status))
            }
            Text(s.items.map { "\($0.article) — \($0.qty) шт" }.joined(separator: ", "))
                .font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(2)
            HStack(spacing: 6) {
                Text(meta).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                if !s.photos.isEmpty { Spacer(); Label("\(s.photos.count)", systemImage: "photo").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Статистика

struct ShipStatsView: View {
    @State private var period = "day"
    @State private var shift = 0
    @State private var stats: ShipStats?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Picker("Период", selection: $period) {
                    Text("День").tag("day"); Text("Неделя").tag("week"); Text("Месяц").tag("month")
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _ in shift = 0 }
                HStack {
                    Button { shift -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    Spacer()
                    Text(stats?.label ?? "…").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { shift += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).disabled(shift >= 0)
                }
            }
            .listRowBackground(Theme.card)
            if let t = stats?.total { totals(t) }
            if let rows = stats?.accounts {
                Section {
                    ForEach(rows) { r in accountRow(r) }
                } header: { Text("По аккаунтам") } footer: { Text("Без отменённых. Стоимость считается только по отправкам, где её заполнили.") }
            }
            if let error { Section { Text(error).foregroundStyle(Theme.red) } }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
        .task(id: period + String(shift)) { await load() }
    }

    private func totals(_ t: ShipStatRow) -> some View {
        Section("Итого") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tile("\(t.ships)", "отправок", "\(t.sent) уже отправлено")
                tile("\(t.qty)", "шт товара", "")
                tile("\(t.returns)", "возвратов", t.defects > 0 ? "\(t.defects) с браком" : "")
                tile(t.costCount > 0 ? shipRub(t.cost) : "—", "стоимость", t.costCount > 0 ? "заполнено в \(t.costCount) из \(t.ships)" : "не заполняли")
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private func tile(_ big: String, _ label: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 24, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func accountRow(_ r: ShipStatRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.name).font(.system(size: 16, weight: .semibold))
            HStack(spacing: 14) {
                stat("отправок", "\(r.ships)")
                stat("штук", "\(r.qty)")
                stat("возвратов", r.defects > 0 ? "\(r.returns) (брак \(r.defects))" : "\(r.returns)")
                stat("стоимость", r.costCount > 0 ? shipRub(r.cost) : "—")
            }
        }
        .listRowBackground(Theme.card)
    }
    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(k).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
    private func load() async {
        do { stats = try await API.shared.get("/api/shipments.php?action=stats&period=\(period)&shift=\(shift)"); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Карточка отправки / возврата

struct ShipmentDetailView: View {
    let shipId: String
    var onChange: () -> Void = {}
    @EnvironmentObject var state: AppState
    @State private var s: Shipment?
    @State private var error: String?
    @State private var busy = false
    @State private var editing: Shipment?
    @State private var makeReturn: Shipment?
    @State private var askCancel = false
    @State private var reason = ""
    @State private var askCheck = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var viewPhoto: ShipPhoto?
    @State private var uploading = false

    var body: some View {
        List { content }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle(s?.isReturn == true ? "Возврат" : "Отправка")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $editing, onDismiss: { Task { await load(); onChange() } }) { e in ShipmentFormView(editing: e) }
            .sheet(item: $makeReturn, onDismiss: { Task { await load(); onChange() } }) { src in ShipmentFormView(editing: nil, kind: "return", source: src) }
            .sheet(isPresented: $askCheck) { CheckSheet { res, cm in Task { await mark("checked", result: res, comment: cm) } } }
            .sheet(item: $viewPhoto) { p in ShipPhotoViewer(photo: p) }
            .fullScreenCover(isPresented: $showCamera) { CameraPicker { img in Task { await addPhotos([img]) } }.ignoresSafeArea() }
            .onChange(of: picks) { items in
                guard !items.isEmpty else { return }
                Task { let imgs = await ShipStore.images(from: items); picks = []; await addPhotos(imgs) }
            }
            .alert(s?.isReturn == true ? "Отменить возврат?" : "Отменить отправку?", isPresented: $askCancel) {
                TextField("Причина", text: $reason)
                Button("Отменить", role: .destructive) { Task { await cancel() } }
                Button("Назад", role: .cancel) {}
            } message: { Text("Карточка в чате отметится как отменённая.") }
            .alert("Ошибка", isPresented: Binding(get: { error != nil && s != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }

    @ViewBuilder private var content: some View {
        if let s {
            header(s)
            links(s)
            itemsSection(s)
            infoSection(s)
            historySection(s)
            photosSection(s)
            actions(s)
        } else if let error {
            ErrorCard(text: error) { Task { await load() } }.listRowBackground(Color.clear)
        } else {
            ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
        }
    }

    private func header(_ s: Shipment) -> some View {
        Section {
            HStack {
                Text((s.isReturn ? "Возврат №" : "Отправка №") + s.id).font(.system(size: 20, weight: .bold))
                Spacer()
                Pill(text: shipStatusText(s.status, isReturn: s.isReturn), color: shipStatusColor(s.status))
            }
        }
    }

    @ViewBuilder private func links(_ s: Shipment) -> some View {
        if s.isReturn && !s.sourceId.isEmpty {
            Section { NavigationLink(value: s.sourceId) { Label("По отправке №\(s.sourceId)", systemImage: "shippingbox") } }
        }
        if !s.isReturn && !s.returnId.isEmpty {
            Section { NavigationLink(value: s.returnId) { Label("Оформлен возврат №\(s.returnId)", systemImage: "arrow.uturn.backward") } }
        }
    }

    private func itemsSection(_ s: Shipment) -> some View {
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
    }

    private func infoSection(_ s: Shipment) -> some View {
        Section(s.isReturn ? "Возврат" : "Доставка") {
            row("Аккаунт Авито", s.account)
            if !s.carrier.isEmpty { row("Транспортная компания", s.carrier) }
            HStack {
                row("Трек-номер", s.track)
                Button { UIPasteboard.general.string = s.track } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless)
            }
            if !s.pvz.isEmpty { row("ПВЗ", s.pvz) }
            if !s.pvzAddress.isEmpty { row("Адрес ПВЗ", s.pvzAddress) }
            if let c = Double(s.cost) { row("Стоимость отправки", shipRub(c)) }
            if !s.comment.isEmpty { row("Комментарий", s.comment) }
        }
    }

    private func historySection(_ s: Shipment) -> some View {
        Section("История") {
            row("Создал", s.createdByName + " · " + shipDate(s.createdAt))
            if !s.packedByName.isEmpty { row("Упаковал", s.packedByName + " · " + shipDate(s.packedAt)) }
            if !s.sentByName.isEmpty { row("Отправил", s.sentByName + " · " + shipDate(s.sentAt)) }
            if !s.receivedByName.isEmpty { row("Получил", s.receivedByName + " · " + shipDate(s.receivedAt)) }
            if !s.checkedByName.isEmpty {
                row("Проверил", s.checkedByName + " · " + shipDate(s.checkedAt))
                row("Состояние", (s.checkResult == "defect" ? "⚠️ Брак" : "👍 Целый") + (s.checkComment.isEmpty ? "" : " — " + s.checkComment))
            }
            if s.status == "cancelled" { row("Отменил", s.cancelledByName + (s.cancelReason.isEmpty ? "" : " · " + s.cancelReason)) }
        }
    }

    private func photosSection(_ s: Shipment) -> some View {
        Section {
            if !s.photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(s.photos) { p in photoCell(p) }
                }
                .padding(.vertical, 4)
            }
            if s.can?.photo == true {
                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                    Label(uploading ? "Загружаю…" : "Добавить из галереи", systemImage: "photo.on.rectangle")
                }
                .disabled(uploading)
                Button { showCamera = true } label: { Label("Сделать фото", systemImage: "camera") }.disabled(uploading)
            }
        } header: { Text(s.photos.isEmpty ? "Фото" : "Фото · \(s.photos.count)") }
    }

    private func photoCell(_ p: ShipPhoto) -> some View {
        Button { viewPhoto = p } label: {
            AuthImage(path: p.path)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if p.by == state.user?.id || state.isBoss {
                Button(role: .destructive) { Task { await deletePhoto(p) } } label: { Label("Удалить фото", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder private func actions(_ s: Shipment) -> some View {
        if let c = s.can, c.pack || c.send || c.unpack || c.receive || c.check || c.unreceive || c.makeReturn || c.edit || c.cancel {
            Section {
                if c.pack { goldBtn("Упакован", "checkmark.seal.fill") { Task { await mark("packed") } } }
                if c.send { goldBtn("Отправлено", "truck.box.fill") { Task { await mark("sent") } } }
                if c.unpack { softBtn("Снять «Упакован»") { Task { await mark("new") } } }
                if c.receive { goldBtn("Получен", "tray.and.arrow.down.fill") { Task { await mark("received") } } }
                if c.check { goldBtn("Проверен", "checkmark.circle.fill") { askCheck = true } }
                if c.unreceive { softBtn("Снять «Получен»") { Task { await mark("await") } } }
                if c.makeReturn { goldBtn("Возврат", "arrow.uturn.backward") { makeReturn = s } }
                if c.edit { softBtn("Изменить") { editing = s } }
                if c.cancel { softBtn(s.isReturn ? "Отменить возврат" : "Отменить отправку", destructive: true) { askCancel = true } }
            }
            .listRowBackground(Color.clear)
            .disabled(busy)
        }
    }

    private func goldBtn(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Label(t, systemImage: icon).frame(maxWidth: .infinity) }.buttonStyle(GoldButtonStyle())
    }
    private func softBtn(_ t: String, destructive: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: a) { Text(t).frame(maxWidth: .infinity) }.buttonStyle(SoftButtonStyle())
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
    private func mark(_ to: String, result: String = "", comment: String = "") async {
        busy = true; defer { busy = false }
        var body: [String: Any] = ["id": Int(shipId) ?? 0, "to": to]
        if to == "checked" { body["result"] = result; body["comment"] = comment }
        do {
            let r: ShipmentResponse = try await API.shared.post("/api/shipments.php?action=mark", body)
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
    private func addPhotos(_ imgs: [UIImage]) async {
        guard !imgs.isEmpty else { return }
        uploading = true; defer { uploading = false }
        do { if let r = try await ShipStore.upload(imgs, to: shipId) { s = r; onChange() } }
        catch { self.error = error.localizedDescription }
    }
    private func deletePhoto(_ p: ShipPhoto) async {
        do { let r: ShipmentResponse = try await API.shared.post("/api/shipments.php?action=photo-delete", ["id": Int(p.id) ?? 0]); s = r.shipment; onChange() }
        catch { self.error = error.localizedDescription }
    }
}

/// «Проверен»: целый или брак + комментарий.
struct CheckSheet: View {
    let onDone: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var result = "ok"
    @State private var comment = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Состояние товара") {
                    Picker("Состояние", selection: $result) {
                        Text("👍 Целый").tag("ok")
                        Text("⚠️ Брак").tag("defect")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Комментарий") {
                    TextField("Например: скол на фланце", text: $comment, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("Возврат проверен")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { onDone(result, comment); dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ShipPhotoViewer: View {
    let photo: ShipPhoto
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AuthImage(path: photo.path).scaledToFit()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

// MARK: - Форма: отправка / возврат

struct ShipmentFormView: View {
    let editing: Shipment?
    var kind: String = "ship"
    var source: Shipment? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var opt: ShipOptions?
    @State private var accountId = ""
    @State private var carrierId = ""
    @State private var items: [ShipItem] = [ShipItem(article: "", name: "", qty: 1)]
    @State private var track = ""
    @State private var comment = ""
    @State private var cost = ""
    @State private var pvz = ""
    @State private var pvzAddress = ""
    @State private var photos: [UIImage] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var error: String?
    @State private var products: [Product] = []
    @State private var pickFor: Int?

    private var isReturn: Bool { (editing?.kind ?? kind) == "return" }

    var body: some View {
        NavigationStack {
            formContent
                .scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(item: pickBinding) { b in pickerSheet(b) }
                .onChange(of: picks) { items in
                    guard !items.isEmpty else { return }
                    Task { let imgs = await ShipStore.images(from: items); photos.append(contentsOf: imgs); picks = [] }
                }
                .task { await setup() }
        }
    }

    private var titleText: String {
        if let e = editing { return (e.isReturn ? "Возврат №" : "Отправка №") + e.id }
        if let src = source { return "Возврат по №\(src.id)" }
        return isReturn ? "Новый возврат" : "Новая отправка"
    }

    private var pickBinding: Binding<IdBox?> {
        Binding(get: { pickFor.map { IdBox(id: String($0)) } }, set: { pickFor = $0.flatMap { Int($0.id) } })
    }

    private func pickerSheet(_ b: IdBox) -> some View {
        ShipCatalogPicker(products: products) { p in
            if let i = Int(b.id), i < items.count { items[i].article = p.article ?? ""; items[i].name = p.name }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button(editing == nil ? "Создать" : "Сохранить") { Task { await save() } }.disabled(busy).fontWeight(.semibold)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Готово") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
    }

    private var formContent: some View {
        Form {
            warningSection
            accountSection
            itemsSection
            carrierSection
            Section(isReturn ? "Трек-номер возврата" : "Трек-номер") {
                TextField("Обязательно", text: $track).textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            extraSection
            Section("Комментарий") {
                TextField("Необязательно", text: $comment, axis: .vertical).lineLimit(2...6)
            }
            if editing == nil { photosSection }
            if let error { Section { Text(error).foregroundStyle(Theme.red) } }
        }
    }

    @ViewBuilder private var extraSection: some View {
        if isReturn {
            Section("ПВЗ (необязательно)") {
                TextField("Название ПВЗ, например «СДЭК, Тверская 12»", text: $pvz)
                TextField("Адрес ПВЗ", text: $pvzAddress, axis: .vertical).lineLimit(1...3)
            }
        } else {
            Section {
                TextField("Например: 450", text: $cost).keyboardType(.decimalPad)
            } header: { Text("Полная стоимость отправки, ₽") } footer: { Text("Необязательно — для статистики.") }
        }
    }

    private var photosSection: some View {
        Section {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.indices, id: \.self) { i in
                            Image(uiImage: photos[i]).resizable().scaledToFill()
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.remove(at: i) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6)) }
                                        .buttonStyle(.plain).padding(3)
                                }
                        }
                    }
                }
            }
            PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                Label("Добавить фото или скриншот", systemImage: "photo.on.rectangle")
            }
        } header: { Text("Фото (необязательно)") }
    }

    @ViewBuilder private var warningSection: some View {
        if let o = opt, o.myAccounts.isEmpty, editing == nil, source == nil {
            Section {
                Text(o.isBoss ? "Сначала добавьте аккаунт Авито: Отправки → ⚙︎ Настройки." : "За вами не закреплён ни один аккаунт Авито — обратитесь к администратору.")
                    .foregroundStyle(Theme.red)
            }
        }
    }

    private var accountList: [ShipAccount] { opt?.myAccounts ?? [] }

    private var accountSection: some View {
        Section("Аккаунт Авито") {
            Picker("Аккаунт", selection: $accountId) {
                ForEach(accountList) { a in Text(a.name).tag(a.id) }
                if let n = extraAccountName { Text(n).tag(accountId) }
            }
        }
    }
    /// Аккаунт исходной отправки может быть не «моим» — показываем его отдельно.
    private var extraAccountName: String? {
        guard !accountId.isEmpty, !accountList.contains(where: { $0.id == accountId }) else { return nil }
        return editing?.account ?? source?.account
    }

    private var carrierSection: some View {
        let all: [ShipCarrier] = opt?.carriers ?? []
        let list: [ShipCarrier] = all.filter { $0.active || $0.id == carrierId }
        return Section("Транспортная компания") {
            Picker("Компания", selection: $carrierId) {
                if isReturn { Text("— не указана").tag("") }
                ForEach(list) { c in Text(c.name).tag(c.id) }
            }
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(items.indices, id: \.self) { i in itemRow(i) }
                .onDelete { idx in if items.count > 1 { items.remove(atOffsets: idx) } }
            Button { items.append(ShipItem(article: "", name: "", qty: 1)) } label: { Label("Ещё товар", systemImage: "plus.circle") }
        } header: { Text("Товары") } footer: { Text("Артикул — вручную или из каталога. Количество можно вписать цифрами. Цена не указывается.") }
    }

    private func articleBinding(_ i: Int) -> Binding<String> {
        Binding(get: { i < items.count ? items[i].article : "" }, set: { v in
            guard i < items.count else { return }
            items[i].article = v
            items[i].name = productName(for: v)
        })
    }
    private func qtyBinding(_ i: Int) -> Binding<String> {
        Binding(get: { i < items.count ? String(items[i].qty) : "1" }, set: { v in
            guard i < items.count else { return }
            let digits = v.filter(\.isNumber)
            items[i].qty = min(10000, max(1, Int(digits.prefix(5)) ?? 1))
        })
    }
    private func qtyStep(_ i: Int) -> Binding<Int> {
        Binding(get: { i < items.count ? items[i].qty : 1 }, set: { v in if i < items.count { items[i].qty = v } })
    }

    private func productName(for article: String) -> String {
        let a = article.trimmingCharacters(in: .whitespaces)
        for p in products where (p.article ?? "").caseInsensitiveCompare(a) == .orderedSame { return p.name }
        return ""
    }

    private func itemRow(_ i: Int) -> some View {
        let name: String = i < items.count ? items[i].name : ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Артикул", text: articleBinding(i))
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button { pickFor = i } label: { Image(systemName: "list.bullet.rectangle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Из каталога")
            }
            if !name.isEmpty { Text(name).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            HStack(spacing: 10) {
                Text("Количество")
                TextField("1", text: qtyBinding(i))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 72)
                    .padding(.vertical, 6)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 8))
                Text("шт").foregroundStyle(Theme.muted)
                Spacer()
                Stepper("", value: qtyStep(i), in: 1...10000).labelsHidden()
            }
        }
    }

    private func setup() async {
        opt = await ShipStore.options()
        if let e = editing {
            accountId = e.accountId; carrierId = e.carrierId; track = e.track; comment = e.comment
            cost = e.cost; pvz = e.pvz; pvzAddress = e.pvzAddress
            items = e.items.isEmpty ? [ShipItem(article: "", name: "", qty: 1)] : e.items
        } else if let src = source {
            accountId = src.accountId; carrierId = src.carrierId
            items = src.items.isEmpty ? [ShipItem(article: "", name: "", qty: 1)] : src.items
        } else {
            if accountId.isEmpty { accountId = opt?.myAccounts.first?.id ?? "" }
            if carrierId.isEmpty && !isReturn { carrierId = opt?.carriers.first { $0.active }?.id ?? "" }
        }
        if let r = try? await API.shared.get("/api/catalog.php?action=bootstrap", as: CatalogResponse.self) {
            products = (r.data?.products ?? []).filter { !($0.article ?? "").isEmpty }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let list = items.filter { !$0.article.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { ["article": $0.article.trimmingCharacters(in: .whitespaces), "name": $0.name, "qty": $0.qty] as [String: Any] }
        var body: [String: Any] = ["kind": isReturn ? "return" : "ship", "accountId": Int(accountId) ?? 0, "carrierId": Int(carrierId) ?? 0, "track": track, "comment": comment, "items": list]
        if isReturn { body["pvz"] = pvz; body["pvzAddress"] = pvzAddress } else { body["cost"] = cost }
        if let src = source { body["sourceId"] = Int(src.id) ?? 0 }
        if let e = editing { body["id"] = Int(e.id) ?? 0 }
        do {
            let r: ShipmentResponse = try await API.shared.post("/api/shipments.php?action=" + (editing == nil ? "create" : "update"), body)
            if !photos.isEmpty { _ = try? await ShipStore.upload(photos, to: r.shipment.id) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Каталог без цен — только название и артикул.
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
                } header: { Text("Работают на складе") } footer: { Text("Они получают уведомления о новых отправках и возвратах и ставят отметки «Упакован», «Отправлено», «Получен», «Проверен». Владелец и администраторы могут ставить отметки всегда.") }

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
