//
//  RootTabView.swift
//  InterestCalculator
//

import SwiftUI
import UIKit

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
            Tab("Profil", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileScreen()
            }
        }
        .preferredColorScheme(state.appearance.colorScheme)
        // Dil seçimi: altındaki tüm metinler, sayılar ve tarihler bu yerel ayarla
        // çözülür (sekme adları, sayfalar ve diyaloglar dahil).
        .environment(\.locale, state.language.locale)
        .onChange(of: scenePhase) { _, phase in
            debugPrint("[RootTabView] Uygulamanın sahne durumu değişti: \(phase).")
            if phase == .active {
                // Öne gelen uygulama günlerce arka planda kalmış olabilir: valörü
                // gelen faiz Bakiyelerim'e eklenir (soğuk açılışı AppState.init yapar).
                state.accrueHoldings()
            } else {
                // Uygulama etkin olmaktan çıkınca (arka plan/inaktif) tüm oturumu kaydet.
                state.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Uygulama açıkken gün döndü (gece yarısı ya da saat/saat dilimi değişti).
            debugPrint("[RootTabView] Gün ya da saat değişti, Bakiyelerim işletiliyor.")
            state.accrueHoldings()
        }
        .onChange(of: state.selectedTab) { _, tab in
            debugPrint("[RootTabView] Sekme değişti: \(tab).")
        }
    }
}

extension AppAppearance {
    /// `.system` için nil: cihazın ayarı geçerli olur.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppState.preview)
}
