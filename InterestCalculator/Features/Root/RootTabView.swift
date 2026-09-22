//
//  RootTabView.swift
//  InterestCalculator
//

import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .summary

    var body: some View {
        TabView(selection: $selection) {
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
