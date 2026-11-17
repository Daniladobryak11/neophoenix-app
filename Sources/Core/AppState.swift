import SwiftUI
import LocalAuthentication

/// Общее состояние: кто вошёл, заказы и заявки. Обновляется с сервера CRM.
@MainActor
final class AppState: ObservableObject {
    enum Phase { case loading, loggedOut, locked, ready }

    @Published var phase: Phase = .loading
    @Published var user: User?
    @Published var orders: [Order] = []
    @Published var leads: [Lead] = []
    @Published var ordersError: String?
    @Published var leadsError: String?
    @Published var lastSync: Date?
    @Published var rooms: [ChatRoom] = []
    @Published var roomsLoaded = false
    @Published var chatsError: String?
    @Published var chatPath: [String] = []
    @Published var work: WorkStatus?
    @Published var workBusy = false

    @AppStorage("faceID") var faceIDEnabled = false
    @AppStorage("theme") var theme = "auto" // auto | light | dark

    var colorScheme: ColorScheme? { theme == "light" ? .light : theme == "dark" ? .dark : nil }
    var newLeads: Int { leads.filter { $0.status == "new" }.count }
    var newOrders: Int { orders.filter { $0.status == "Новый" }.count }
    var unreadChats: Int { rooms.reduce(0) { $0 + $1.unread } }
    var onShift: Bool { work?.open != nil }

    init() {
        API.shared.onUnauthorized = { [weak self] in self?.signOutLocally() }
    }

    func start() async {
        guard API.shared.token != nil else { phase = .loggedOut; return }
        if faceIDEnabled { phase = .locked; return }
        await loadMe()
    }

    func loadMe() async {
        do {
            let me: MeResponse = try await API.shared.get("/api/app.php?action=me")
            user = me.user
            phase = .ready
            await refreshAll()
        } catch let e as APIError where e.status == 401 {
            signOutLocally()
        } catch {
            // нет интернета — пускаем в приложение, данные подтянутся позже
            phase = .ready
        }
    }

    func login(email: String, password: String) async throws {
        let device = UIDevice.current.name
        let r: LoginResponse = try await API.shared.post("/api/app.php?action=login", ["email": email, "password": password, "device": device])
        API.shared.token = r.token
        user = r.user
        phase = .ready
        await refreshAll()
    }

    func unlockWithFaceID() async {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { await loadMe(); return }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Вход в «Нео Феникс»")
            if ok { await loadMe() }
        } catch { /* остаёмся на экране блокировки */ }
    }

    func logout() async {
        _ = try? await API.shared.post("/api/app.php?action=logout", as: OkResponse.self)
        signOutLocally()
    }

    func signOutLocally() {
        API.shared.token = nil
        user = nil; orders = []; leads = []; rooms = []; work = nil; chatPath = []
        phase = .loggedOut
    }

    func refreshAll() async {
        async let a: Void = refreshOrders()
        async let b: Void = refreshLeads()
        async let c: Void = refreshRooms()
        async let d: Void = refreshWork()
        _ = await (a, b, c, d)
        lastSync = Date()
    }

    func refreshOrders() async {
        do { let r: OrdersResponse = try await API.shared.get("/api/orders.php?action=list"); orders = r.orders; ordersError = nil }
        catch { ordersError = error.localizedDescription }
    }

    func refreshLeads() async {
        do { let r: LeadsResponse = try await API.shared.get("/api/leads.php?action=list"); leads = r.leads; leadsError = nil }
        catch { leadsError = error.localizedDescription }
    }

    func refreshRooms() async {
        do { let r: RoomsResponse = try await API.shared.get("/api/chat.php?action=rooms"); rooms = r.rooms; chatsError = nil }
        catch { chatsError = error.localizedDescription }
        roomsLoaded = true
    }

    func refreshWork() async {
        if let w: WorkStatus = try? await API.shared.get("/api/worktime.php?action=status") { work = w }
    }

    /// Начать или закончить смену. Возвращает текст ошибки, если сервер отказал.
    func toggleShift() async -> String? {
        workBusy = true; defer { workBusy = false }
        do {
            let w: WorkStatus = try await API.shared.post("/api/worktime.php?action=" + (onShift ? "stop" : "start"))
            work = w
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return nil
        } catch { return error.localizedDescription }
    }

    // MARK: действия

    func takeOrder(_ o: Order) async throws {
        let r: OrdersResponse = try await API.shared.post("/api/orders.php?action=take", ["id": o.id])
        orders = r.orders
    }

    func setStatus(_ o: Order, _ status: String) async throws {
        let r: OrdersResponse = try await API.shared.post("/api/orders.php?action=update", ["id": o.id, "status": status])
        orders = r.orders
    }

    func takeLead(_ l: Lead) async throws {
        let r: LeadsResponse = try await API.shared.post("/api/leads.php?action=take", ["id": l.id])
        leads = r.leads
    }

    func setLeadStatus(_ l: Lead, _ status: String, comment: String? = nil) async throws {
        var body: [String: Any] = ["id": l.id, "status": status]
        if let comment { body["comment"] = comment }
        let r: LeadsResponse = try await API.shared.post("/api/leads.php?action=update", body)
        leads = r.leads
    }

    func createLead(_ fields: [String: Any]) async throws {
        let r: LeadsResponse = try await API.shared.post("/api/leads.php?action=staff-create", fields)
        leads = r.leads
    }
}
