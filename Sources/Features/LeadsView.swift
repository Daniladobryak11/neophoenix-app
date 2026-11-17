import SwiftUI

struct LeadsView: View {
    @EnvironmentObject var state: AppState
    @State private var tab = "new"
    @State private var error: String?
    @State private var busyId: String?
    @Environment(\.openURL) private var openURL

    private var list: [Lead] {
        switch tab {
        case "new": return state.leads.filter { $0.status == "new" }
        case "work": return state.leads.filter { $0.status == "work" }
        default: return state.leads.filter { $0.status == "done" || $0.status == "spam" }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Picker("", selection: $tab) {
                        Text("Новые · \(state.leads.filter { $0.status == "new" }.count)").tag("new")
                        Text("В работе").tag("work")
                        Text("Закрытые").tag("done")
                    }
                    .pickerStyle(.segmented)

                    if let e = state.leadsError, state.leads.isEmpty {
                        ErrorCard(text: e) { Task { await state.refreshLeads() } }
                    } else if list.isEmpty {
                        EmptyCard(icon: "bubble.left", text: tab == "new" ? "Новых заявок нет" : "Здесь пока пусто")
                    }
                    ForEach(list) { l in leadCard(l) }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
            .background(Theme.bg)
            .refreshable { await state.refreshLeads() }
            .navigationTitle("Заявки")
            .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func leadCard(_ l: Lead) -> some View {
        let isNew = l.status == "new"
        let waitMin = parseISO(l.createdAt).map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Pill(text: l.statusLabel, color: isNew ? Theme.red : l.status == "work" ? Theme.blue : Theme.muted)
                Text(l.kindLabel).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(ago(l.createdAt)).font(.system(size: 12)).foregroundStyle(isNew ? Theme.red : Theme.muted)
            }
            Text(l.name.isEmpty ? l.phone : "\(l.name) · \(l.phone)").font(.system(size: 16, weight: .semibold))
            if !l.details.isEmpty { Text(l.details).font(.system(size: 14)).foregroundStyle(Theme.muted) }
            if let m = l.managerName, !m.isEmpty { Text("Взял: \(m)").font(.system(size: 13)).foregroundStyle(Theme.muted) }
            HStack(spacing: 8) {
                if isNew {
                    Button { Task { await take(l) } } label: {
                        if busyId == l.id { ProgressView().tint(Theme.onGold) } else { Text("Взять") }
                    }.buttonStyle(GoldButtonStyle())
                } else if l.status == "work" {
                    Button { Task { await done(l) } } label: { Text("Обработана") }.buttonStyle(SoftButtonStyle(tint: Theme.green))
                }
                Button { call(l.phone) } label: { Label("Позвонить", systemImage: "phone.fill") }.buttonStyle(SoftButtonStyle())
            }
            if isNew && waitMin < 15 {
                Text("⏱ Осталось \(15 - waitMin) мин, потом напомним всем на смене").font(.system(size: 12)).foregroundStyle(Theme.red)
            }
        }
        .card(padding: 14)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(isNew ? Theme.red.opacity(0.45) : .clear, lineWidth: 1.5))
    }

    private func take(_ l: Lead) async {
        busyId = l.id; defer { busyId = nil }
        do { try await state.takeLead(l); UINotificationFeedbackGenerator().notificationOccurred(.success) }
        catch { self.error = error.localizedDescription }
    }
    private func done(_ l: Lead) async {
        do { try await state.setLeadStatus(l, "done") } catch { self.error = error.localizedDescription }
    }
    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let u = URL(string: "tel:\(digits)") { openURL(u) }
    }
}
