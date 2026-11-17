import SwiftUI

@main
struct NeoPhoenixApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
                .tint(Theme.gold)
                .task { await state.start() }
                .onChange(of: scenePhase) { phase in
                    // вернулись в приложение — подтягиваем свежие заказы и заявки
                    if phase == .active, state.phase == .ready { Task { await state.refreshAll() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch state.phase {
            case .loading: SplashView()
            case .loggedOut: LoginView()
            case .locked: LockView()
            case .ready: MainTabs()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.phase)
    }
}

struct SplashView: View {
    var body: some View {
        Image("Phoenix").resizable().scaledToFit().frame(width: 140)
    }
}

struct MainTabs: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        TabView(selection: $state.selectedTab) {
            OrdersView()
                .tabItem { Label("Заказы", systemImage: "doc.text") }
                .badge(state.newOrders).tag(0)
            LeadsView()
                .tabItem { Label("Заявки", systemImage: "bubble.left") }
                .badge(state.newLeads).tag(1)
            ShipmentsView()
                .tabItem { Label("Отправки", systemImage: "shippingbox") }
                .tag(5)
            TasksView()
                .tabItem { Label("Задачи", systemImage: "checkmark.square") }
                .badge(state.myTasksOpen).tag(2)
            ChatsView()
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right") }
                .badge(state.unreadChats).tag(3)
        }
    }
}

struct ComingSoonView: View {
    let title: String
    let icon: String
    let text: String
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 44, weight: .light)).foregroundStyle(Theme.gold)
                Text(text).font(.system(size: 15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle(title)
        }
    }
}

/// Аватар слева сверху на каждой вкладке — открывает «Я» (профиль, смена, сотрудники, выход).
struct MeButtonModifier: ViewModifier {
    @EnvironmentObject var state: AppState
    @State private var show = false
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { show = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(userId: state.user?.id, name: state.user?.name ?? "", size: 30)
                            if state.work?.open != nil { Circle().fill(Theme.green).frame(width: 9, height: 9).overlay(Circle().stroke(Theme.bg, lineWidth: 2)) }
                        }
                    }
                    .accessibilityLabel("Мой профиль")
                }
            }
            .sheet(isPresented: $show) { MeView().environmentObject(state).preferredColorScheme(state.colorScheme) }
    }
}
extension View { func meButton() -> some View { modifier(MeButtonModifier()) } }
