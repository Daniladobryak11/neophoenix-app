import SwiftUI

/// Новый заказ — из заявки (имя, телефон, машина подставляются) или с нуля.
struct NewOrderView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var lead: Lead? = nil

    struct Line: Identifiable, Hashable {
        let id = UUID()
        var productId: String
        var name: String
        var price: Double
        var qty: Int
    }

    @State private var client = ""
    @State private var phone = ""
    @State private var source = "Сайт"
    @State private var comment = ""
    @State private var lines: [Line] = []
    @State private var products: [Product] = []
    @State private var showPicker = false
    @State private var customName = ""
    @State private var customPrice = ""
    @State private var busy = false
    @State private var error: String?
    @State private var requestId = UUID().uuidString.lowercased()

    private var total: Double { lines.reduce(0) { $0 + $1.price * Double($1.qty) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Клиент") {
                    TextField("Имя", text: $client)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                    Picker("Источник", selection: $source) {
                        ForEach(["Сайт", "Авито", "Розница"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Товары") {
                    ForEach($lines) { $l in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l.name).font(.system(size: 15))
                            HStack {
                                Stepper("\(l.qty) шт", value: $l.qty, in: 1...1000).fixedSize()
                                Spacer()
                                Text(rub(l.price * Double(l.qty))).font(.system(size: 15, weight: .semibold))
                            }
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    Button { showPicker = true } label: { Label("Добавить из каталога", systemImage: "plus.circle") }
                    HStack {
                        TextField("Свой товар", text: $customName)
                        TextField("Цена", text: $customPrice).keyboardType(.decimalPad).frame(width: 90)
                        Button {
                            let p = Double(customPrice.replacingOccurrences(of: ",", with: ".")) ?? -1
                            guard customName.trimmingCharacters(in: .whitespaces).count >= 2, p >= 0 else { error = "Укажите название и цену товара"; return }
                            lines.append(Line(productId: "", name: customName.trimmingCharacters(in: .whitespaces), price: p, qty: 1))
                            customName = ""; customPrice = ""
                        } label: { Image(systemName: "plus") }
                    }
                    if !lines.isEmpty {
                        HStack { Text("Итого").font(.system(size: 16, weight: .semibold)); Spacer(); Text(rub(total)).font(.system(size: 17, weight: .bold)) }
                    }
                }
                Section("Комментарий") {
                    TextField("Машина, договорённости, доставка", text: $comment, axis: .vertical).lineLimit(2...6)
                }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle(lead == nil ? "Новый заказ" : "Заказ из заявки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("Создать") } }
                        .disabled(busy || lines.isEmpty || client.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
            .sheet(isPresented: $showPicker) {
                ProductPicker(products: products) { p in lines.append(Line(productId: p.id, name: p.name, price: p.price, qty: 1)) }
            }
            .task {
                if let l = lead, client.isEmpty {
                    client = l.name; phone = l.phone
                    source = l.source == "Авито" ? "Авито" : "Сайт"
                    comment = [l.car.map { "Авто: \($0)" }, l.product.map { "Товар: \($0)" }, l.message]
                        .compactMap { $0 }.filter { !$0.isEmpty && $0 != "Авто: " && $0 != "Товар: " }.joined(separator: "\n")
                }
                if products.isEmpty, let r = try? await API.shared.get("/api/catalog.php?action=bootstrap", as: CatalogResponse.self) {
                    products = r.data?.products ?? []
                }
            }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let items: [[String: Any]] = lines.map { ["id": $0.productId, "name": $0.name, "price": $0.price, "qty": $0.qty] }
        do {
            let r: CreatedOrderResponse = try await API.shared.post("/api/orders.php?action=staff-create", [
                "requestId": requestId, "source": source, "client": client.trimmingCharacters(in: .whitespaces),
                "phone": phone, "comment": comment, "status": "Новый", "items": items,
            ])
            if let o = r.orders { state.orders = o }
            if let l = lead, let oid = r.id {
                _ = try? await API.shared.post("/api/leads.php?action=update", ["id": l.id, "status": "done", "orderId": oid, "comment": (l.comment ?? "")], as: LeadsResponse.self)
                await state.refreshLeads()
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ProductPicker: View {
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
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).foregroundStyle(Theme.text)
                            Text(p.stock > 0 ? "в наличии: \(p.stock)" : "нет в наличии").font(.system(size: 12)).foregroundStyle(p.stock > 0 ? Theme.green : Theme.muted)
                        }
                        Spacer()
                        Text(rub(p.price)).foregroundStyle(Theme.text)
                    }
                }
            }
            .overlay { if products.isEmpty { ProgressView() } }
            .searchable(text: $q, prompt: "Название или артикул")
            .navigationTitle("Каталог")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}
