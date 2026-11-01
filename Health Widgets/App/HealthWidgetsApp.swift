import SwiftUI

@main
struct HealthWidgetsApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .dashboard:
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Aujourd'hui", systemImage: "heart.text.square.fill", value: AppModel.Tab.today) {
                DashboardView()
            }
            Tab("Widgets", systemImage: "square.grid.2x2.fill", value: AppModel.Tab.widgets) {
                WidgetGalleryView()
            }
            Tab("Réglages", systemImage: "gearshape.fill", value: AppModel.Tab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
