//
//  RootTabView.swift
//  InterestCalculator
//

import SwiftUI

struct RootTabView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var state = state
        TabView(selection: $state.selectedTab) {
            Tab("Özet", systemImage: "moon.stars", value: AppTab.summary) {
                SummaryScreen()
            }
            Tab("Düzenle", systemImage: "building.columns", value: AppTab.editor) {
                EditorScreen()
            }
            Tab("Karşılaştır", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.compare) {
                CompareScreen()
            }
            Tab("Max", systemImage: "gauge.with.dots.needle.100percent", value: AppTab.max) {
                MaxScreen()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Uygulama etkin olmaktan çıkınca (arka plan/inaktif) tüm oturumu kaydet.
            if phase != .active { state.save() }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppState.preview)
}
