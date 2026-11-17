import SwiftUI

/// Задачи — те же, что в CRM: мои, поручил, все (для руководителя).
struct TasksView: View {
    @EnvironmentObject var state: AppState
    @State private var filter = "mine"
    @State private var showNew = false
    @State private var showDone = false

    private var list: [TaskItem] {
        let me = state.user?.id
        var l: [TaskItem]
        switch filter {
        case "mine": l = state.tasks.filter { $0.responsibleId == me }
        case "given": l = state.tasks.filter { $0.creatorId == me && $0.responsibleId != me }
        default: l = state.tasks
        }
        if !showDone { l = l.filter { $0.isOpen } }
        return l.sorted { a, b in
            if a.overdue != b.overdue { return a.overdue }
            let da = a.deadlineDate ?? .distantFuture, db = b.deadlineDate ?? .distantFuture
            return da < db
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $filter) {
                    Text("Мои").tag("mine")
                    Text("Поручил").tag("given")
                    Text("Все").tag("all")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                let overdue = list.filter { $0.overdue }.count
                if overdue > 0 {
                    Label(overdue == 1 ? "1 задача просрочена" : "\(overdue) задачи просрочены", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.red).font(.system(size: 14, weight: .semibold))
                        .listRowBackground(Theme.red.opacity(0.12))
                }
                if let e = state.tasksError, state.tasks.isEmpty {
                    ErrorCard(text: e) { Task { await state.refreshTasks() } }.listRowBackground(Color.clear)
                } else if list.isEmpty {
                    EmptyCard(icon: "checkmark.square", text: state.tasksLoaded ? "Задач нет" : "Загружаю задачи…").listRowBackground(Color.clear)
                }
                ForEach(list) { t in
                    NavigationLink(value: t.id) { TaskRow(task: t) }.listRowBackground(Theme.card)
                }
                Toggle("Показывать выполненные", isOn: $showDone).font(.system(size: 14)).listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .refreshable { await state.refreshTasks() }
            .navigationTitle("Задачи")
            .meButton()
            .navigationDestination(for: String.self) { id in TaskDetailView(taskId: id) }
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showNew) { NewTaskView() }
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var state: AppState
    let task: TaskItem
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.status == "done" ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22)).foregroundStyle(task.status == "done" ? Theme.green : taskStatusColor(task.status))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if task.priority == "high" { Text("🔥") }
                    Text(task.title).font(.system(size: 16, weight: .semibold)).strikethrough(task.status == "done").lineLimit(2)
                }
                HStack(spacing: 6) {
                    Pill(text: task.statusLabel, color: taskStatusColor(task.status))
                    if let d = task.deadlineDate {
                        Text(deadlineText(d)).font(.system(size: 12, weight: task.overdue ? .semibold : .regular)).foregroundStyle(task.overdue ? Theme.red : Theme.muted)
                    }
                }
                HStack(spacing: 6) {
                    Avatar(userId: task.responsibleId, name: task.responsibleName, size: 18)
                    Text(task.responsibleName).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    if !task.orderNumber.isEmpty { Text("· \(task.orderNumber)").font(.system(size: 12)).foregroundStyle(Theme.gold).lineLimit(1) }
                    if task.checkTotal > 0 { Text("· ☑︎ \(task.checkDone)/\(task.checkTotal)").font(.system(size: 12)).foregroundStyle(Theme.muted) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

func deadlineText(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU")
    if Calendar.current.isDateInToday(d) { f.dateFormat = "'сегодня до' HH:mm" }
    else if Calendar.current.isDateInTomorrow(d) { f.dateFormat = "'завтра до' HH:mm" }
    else { f.dateFormat = "d MMM, HH:mm" }
    return f.string(from: d)
}

struct TaskDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let taskId: String
    @State private var task: TaskItem?
    @State private var comment = ""
    @State private var newCheck = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pickResp = false
    @State private var askReturn = false
    @State private var returnNote = ""
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let t = task {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Pill(text: t.statusLabel, color: taskStatusColor(t.status)); if t.priority == "high" { Text("🔥 Важная").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.red) } }
                        Text(t.title).font(.system(size: 20, weight: .bold))
                        if !t.description.isEmpty { Text(t.description).font(.system(size: 15)).foregroundStyle(Theme.text) }
                        if let d = t.deadlineDate { Label(deadlineText(d), systemImage: "clock").font(.system(size: 14)).foregroundStyle(t.overdue ? Theme.red : Theme.muted) }
                        if !t.orderNumber.isEmpty { Label("Заказ \(t.orderNumber)", systemImage: "doc.text").font(.system(size: 14)).foregroundStyle(Theme.gold) }
                        Text("Поставил: \(t.creatorName)").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                    ResponsibleRow(userId: t.responsibleId, name: t.responsibleName, canChange: t.can?.edit == true) { pickResp = true }
                }
                actions(t)
                if !t.checklist.isEmpty || t.can?.check == true {
                    Section("Чек-лист · \(t.checklist.filter { $0.done }.count)/\(t.checklist.count)") {
                        ForEach(t.checklist) { c in
                            Button { Task { await call("check", ["op": "toggle", "itemId": Int(c.id) ?? 0]) } } label: {
                                Label { Text(c.text).strikethrough(c.done).foregroundStyle(c.done ? Theme.muted : Theme.text) }
                                    icon: { Image(systemName: c.done ? "checkmark.square.fill" : "square").foregroundStyle(c.done ? Theme.green : Theme.muted) }
                            }
                            .disabled(t.can?.check != true)
                        }
                        if t.can?.check == true {
                            HStack {
                                TextField("Новый пункт", text: $newCheck)
                                Button { let s = newCheck; newCheck = ""; Task { await call("check", ["op": "add", "text": s]) } } label: { Image(systemName: "plus.circle.fill") }
                                    .disabled(newCheck.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
                Section("Комментарии и история") {
                    ForEach(t.feed) { f in
                        HStack(alignment: .top, spacing: 10) {
                            Avatar(userId: f.userId, name: f.name, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(f.name).font(.system(size: 13, weight: .semibold)); Spacer(); if let d = parseISO(f.createdAt) { Text(shortTime(d)).font(.system(size: 11)).foregroundStyle(Theme.muted) } }
                                Text(f.body).font(.system(size: 14)).foregroundStyle(f.kind == "system" ? Theme.muted : Theme.text).italic(f.kind == "system")
                            }
                        }
                    }
                    if t.can?.comment == true {
                        HStack(alignment: .bottom) {
                            TextField("Комментарий", text: $comment, axis: .vertical).lineLimit(1...5)
                            Button { let s = comment; comment = ""; Task { await call("comment", ["body": s]) } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 26)) }
                                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if t.can?.delete == true {
                    Section { Button("Удалить задачу", role: .destructive) { confirmDelete = true } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Задача").navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $pickResp) {
            StaffPicker(title: "Ответственный", selected: task?.responsibleId) { id in Task { await call("update", ["responsible": Int(id) ?? 0]) } }
        }
        .alert("Что нужно доделать?", isPresented: $askReturn) {
            TextField("Комментарий", text: $returnNote)
            Button("Вернуть") { let n = returnNote; returnNote = ""; Task { await call("status", ["to": "work", "comment": n]) } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить задачу?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await deleteTask() } }
        }
        .alert("Не получилось", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Понятно", role: .cancel) {} } message: { Text(error ?? "") }
    }

    @ViewBuilder private func actions(_ t: TaskItem) -> some View {
        let can = t.can
        if can?.start == true || can?.finish == true || can?.accept == true || can?.ret == true || can?.defer_ == true {
            Section {
                if can?.start == true && (t.status == "new" || t.status == "deferred") {
                    Button { Task { await call("status", ["to": "work"]) } } label: { Text("Взять в работу") }.buttonStyle(GoldButtonStyle())
                }
                if can?.finish == true && t.status != "done" && t.status != "review" {
                    Button { Task { await call("status", ["to": "review"]) } } label: { Text("Готово") }.buttonStyle(t.status == "work" ? AnyButtonStyle(GoldButtonStyle()) : AnyButtonStyle(SoftButtonStyle(tint: Theme.green)))
                }
                if can?.accept == true && t.status == "review" {
                    Button { Task { await call("status", ["to": "done"]) } } label: { Text("Принять работу") }.buttonStyle(GoldButtonStyle())
                }
                if can?.ret == true && (t.status == "review" || t.status == "done") {
                    Button { askReturn = true } label: { Text("Вернуть на доработку") }.buttonStyle(SoftButtonStyle(tint: Theme.amber))
                }
                if can?.defer_ == true && t.status != "deferred" && t.status != "done" {
                    Button { Task { await call("status", ["to": "deferred"]) } } label: { Text("Отложить") }.buttonStyle(SoftButtonStyle(tint: Theme.muted))
                }
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .disabled(busy)
        }
    }

    private func load() async {
        do { let r: TaskResponse = try await API.shared.get("/api/tasks.php?action=get&id=\(taskId)"); task = r.task }
        catch { self.error = error.localizedDescription }
    }

    private func call(_ action: String, _ extra: [String: Any]) async {
        busy = true; defer { busy = false }
        var body = extra; body["id"] = Int(taskId) ?? 0
        do {
            let r: TaskResponse = try await API.shared.post("/api/tasks.php?action=\(action)", body)
            task = r.task
            UISelectionFeedbackGenerator().selectionChanged()
            await state.refreshTasks()
        } catch { self.error = error.localizedDescription }
    }

    private func deleteTask() async {
        do {
            _ = try await API.shared.post("/api/tasks.php?action=delete", ["id": Int(taskId) ?? 0], as: OkResponse.self)
            await state.refreshTasks()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct NewTaskView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var orderId: String? = nil
    var presetTitle: String = ""
    @State private var title = ""
    @State private var description = ""
    @State private var responsible = ""
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date()
    @State private var important = false
    @State private var pick = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Что сделать", text: $title, axis: .vertical).lineLimit(1...3)
                    TextField("Подробности", text: $description, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    ResponsibleRow(userId: responsible, name: state.profile(responsible)?.name, canChange: true) { pick = true }
                    Toggle("Срок", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("До", selection: $deadline, in: Date()...).environment(\.locale, Locale(identifier: "ru_RU")) }
                    Toggle("🔥 Важная", isOn: $important)
                }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Новая задача").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("Создать") } }
                        .disabled(busy || title.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            .sheet(isPresented: $pick) { StaffPicker(title: "Ответственный", selected: responsible) { responsible = $0 } }
            .onAppear { if responsible.isEmpty { responsible = state.user?.id ?? "" }; if title.isEmpty { title = presetTitle } }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Moscow"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var body: [String: Any] = ["title": title.trimmingCharacters(in: .whitespacesAndNewlines), "description": description,
                                   "responsible": Int(responsible) ?? 0, "priority": important ? "high" : "normal",
                                   "deadline": hasDeadline ? f.string(from: deadline) : ""]
        if let orderId { body["orderId"] = Int(orderId) ?? 0 }
        do {
            _ = try await API.shared.post("/api/tasks.php?action=create", body, as: TaskResponse.self)
            await state.refreshTasks()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
