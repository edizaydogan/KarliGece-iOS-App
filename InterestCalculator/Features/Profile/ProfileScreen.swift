//
//  ProfileScreen.swift
//  InterestCalculator
//
//  Tab 5 — Profil. Ayarlar tarzı menü listesi: profil kartı (kişisel
//  bilgiler), Bakiyelerim, görünüm tercihi ve Hakkında. Sekmenin kendi
//  NavigationStack'i vardır; kökte çubuk gizli (Max gibi), başlık yalnız
//  alt sayfalardaki geri düğmesinde görünür.
//  Zemin düz snowfield — gece gradyanı yalnız Özet'in.
//

import SwiftUI

/// Profil sekmesinin sayfaları.
enum ProfileRoute: Hashable {
    case personalInfo
    case holdings
    case holding(UUID)
    case about
}

struct ProfileScreen: View {
    @Environment(AppState.self) private var state
    @State private var path: [ProfileRoute] = []

    var body: some View {
        @Bindable var state = state

        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: ProfileRoute.personalInfo) {
                        header
                    }
                    .accessibilityIdentifier("profileHeader")
                }
                .listRowBackground(Color.drift)

                Section("Hesaplarım") {
                    NavigationLink(value: ProfileRoute.holdings) {
                        ProfileMenuRow(systemImage: "banknote", tint: .aurora,
                                       title: "Bakiyelerim", subtitle: holdingsSubtitle)
                    }
                    .accessibilityIdentifier("profileHoldingsRow")
                }
                .listRowBackground(Color.drift)

                Section("Tercihler") {
                    Picker(selection: $state.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    } label: {
                        ProfileMenuRow(systemImage: "circle.lefthalf.filled", tint: .glacier, title: "Görünüm")
                    }
                    .pickerStyle(.menu)
                    .tint(.slate)
                    .onChange(of: state.appearance) { _, appearance in
                        debugPrint("[ProfileScreen] Görünüm tercihi değişti: \(appearance).")
                    }
                    .accessibilityIdentifier("profileAppearancePicker")
                }
                .listRowBackground(Color.drift)

                Section("Uygulama") {
                    NavigationLink(value: ProfileRoute.about) {
                        ProfileMenuRow(systemImage: "info", tint: .slate,
                                       title: "Hakkında", subtitle: "Hesaplama kuralları ve sürüm")
                    }
                    .accessibilityIdentifier("profileAboutRow")
                }
                .listRowBackground(Color.drift)
            }
            .scrollContentBackground(.hidden)
            .background(Color.snowfield)
            .accessibilityIdentifier("profileRoot")
            .navigationTitle("Profil")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .personalInfo:     PersonalInfoScreen()
                case .holdings:         HoldingsScreen()
                case .holding(let id):  HoldingDetailScreen(holdingID: id)
                case .about:            AboutScreen()
                }
            }
        }
        .onChange(of: path) { _, path in
            debugPrint("[ProfileScreen] Profil sayfası değişti: \(path.last.map { "\($0)" } ?? "kök").")
        }
    }

    // MARK: - Profil kartı

    private var header: some View {
        let name = state.profile.fullName
        return HStack(spacing: 14) {
            ProfileAvatar(initials: state.profile.initials, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? "Profilinizi oluşturun")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.ink)
                Text(name == nil ? "Adınızı eklemek için dokunun" : "Kişisel bilgiler")
                    .font(.subheadline)
                    .foregroundStyle(.slate)
            }
        }
        .padding(.vertical, 6)
    }

    private var holdingsSubtitle: String {
        guard !state.holdings.isEmpty else { return "Bankalardaki gerçek bakiyeleriniz" }
        return "\(state.holdings.count) banka · \(state.totalHoldingsBalance.formatted(.currency(code: "TRY")))"
    }
}

#Preview {
    ProfileScreen()
        .environment(AppState.preview)
}
