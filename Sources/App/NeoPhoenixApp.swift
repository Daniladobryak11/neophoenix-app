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
        TabView {
            OrdersView()
                .tabItem { Label("Заказы", systemImage: "doc.text") }
                .badge(state.newOrders)
            LeadsView()
                .tabItem { Label("Заявки", systemImage: "bubble.left") }
                .badge(state.newLeads)
            ComingSoonView(title: "Задачи", icon: "checkmark.square", text: "Мои задачи, сроки и отметка «выполнено» — в следующей версии.")
                .tabItem { Label("Задачи", systemImage: "checkmark.square") }
            ComingSoonView(title: "Чаты", icon: "bubble.left.and.bubble.right", text: "Чаты с коллегами, фото и карточки заказов — в следующей версии.")
                .tabItem { Label("Чаты", systemImage: "bubble.left.and.bubble.right") }
            MeView()
                .tabItem { Label("Я", systemImage: "person.crop.circle") }
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
