import SwiftUI

/// Смена: «Начать смену» / «Закончить смену», таймер и часы за день и месяц.
struct ShiftCard: View {
    @EnvironmentObject var state: AppState
    @State private var error: String?
    @State private var confirmStop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(state.onShift ? Theme.green : Theme.muted).frame(width: 10, height: 10)
                    .shadow(color: state.onShift ? Theme.green.opacity(0.6) : .clear, radius: 4)
                Text(state.onShift ? "На смене" : "Не на смене").font(.system(size: 16, weight: .semibold))
                Spacer()
                if let s = state.work?.open { Text("с \(s.start)").font(.system(size: 14)).foregroundStyle(Theme.muted) }
            }
            if let s = state.work?.open {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(elapsed(s, now: ctx.date)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            Text(summary).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Button {
                if state.onShift { confirmStop = true } else { Task { error = await state.toggleShift() } }
            } label: {
                if state.workBusy { ProgressView() } else { Text(state.onShift ? "Закончить смену" : "Начать смену") }
            }
            .buttonStyle(state.onShift ? AnyButtonStyle(SoftButtonStyle()) : AnyButtonStyle(GoldButtonStyle()))
            .disabled(state.workBusy || state.work == nil)
            if let w = state.work?.window, !w.inWindow && !state.onShift {
                Text("Отметиться можно с \(w.open) до \(w.close) по Москве").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .card()
        .confirmationDialog("Закончить смену сейчас?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Закончить смену") { Task { error = await state.toggleShift() } }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(error ?? "") }
        .task { if state.work == nil { await state.refreshWork() } }
    }

    private var summary: String {
        let t = state.work?.today?.minutes ?? 0, m = state.work?.month?.minutes ?? 0
        return "Сегодня \(hoursText(t)) · за месяц \(hoursText(m))"
    }
    private func elapsed(_ s: Shift, now: Date) -> String {
        guard let iso = s.startIso, let st = parseISO(iso) else { return hoursText(s.minutes) }
        let mins = max(0, Int(now.timeIntervalSince(st) / 60))
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }
}

/// Чтобы выбирать стиль кнопки по условию.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Плашка над заказами, если смена не начата.
struct ShiftBanner: View {
    @EnvironmentObject var state: AppState
    @State private var error: String?
    var body: some View {
        if state.work != nil && !state.onShift {
            HStack(spacing: 12) {
                Image(systemName: "clock").font(.system(size: 18)).foregroundStyle(Theme.gold)
                Text("Вы не на смене").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { Task { error = await state.toggleShift() } } label: {
                    Text("Начать").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onGold)
                        .padding(.horizontal, 16).frame(height: 34).background(Theme.goldFill, in: Capsule())
                }
                .disabled(state.workBusy)
            }
            .card(padding: 12)
            .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}
