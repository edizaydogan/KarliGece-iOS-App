//
//  RootTabView.swift
//  InterestCalculator
//

import SwiftUI

struct RootTabView: View {
    @Environment(AppState.self) private var state

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
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppState.preview)
}
