//
//  HoldingsScreen.swift
//  InterestCalculator
//
//  Profil → Bakiyelerim. Bankalardaki GERÇEK bakiyeler: toplam, eklenen faiz,
//  gecelik net kazanç ve kayıt listesi. Her kayıt Düzenle'deki bir bankaya
//  bağlıdır; uygulama her açılışta valörü gelen net faizi o bankanın
//  koşullarıyla bakiyeye ekler (AppState.accrueHoldings). Bu ekran hesap
//  YAPMAZ, işletilmiş kayıtları gösterir.
//

import SwiftUI

struct HoldingsScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 36
    @State private var isAdding = false

    private let accrualNote: LocalizedStringKey = "Faiz, bağlı bankanın Düzenle'deki koşulları ve stopajla her açılışta eklenir: hafta içi kazanç ertesi gün, hafta sonu kazancı kaydın seçimine göre her gece (1 gecelik) ya da Pazartesi toplu (3 gecelik). Bankanızın tahakkukundan kuruş farkı olabilir; gerekirse bakiyeyi düzeltin."

    var body: some View {
        List {
            if !state.holdings.isEmpty {
                Section {
                    summary
                }
                .listRowBackground(Color.drift)
            }

            Section {
                if state.holdings.isEmpty {
                    emptyRow
                }
                ForEach(Array(state.holdings.enumerated()), id: \.element.id) { index, holding in
                    NavigationLink(value: ProfileRoute.holding(holding.id)) {
                        row(holding)
                    }
                    .accessibilityIdentifier("holdingRow_\(index)")
                }
                .onDelete { state.deleteHoldings(at: $0) }

                Button {
                    isAdding = true
                } label: {
                    Label("Bakiye ekle", systemImage: "plus")
                }
                .foregroundStyle(.glacier)
                .accessibilityIdentifier("holdingsAddButton")
            } header: {
                Text("Hesaplar")
            } footer: {
                Text(accrualNote).foregroundStyle(.slate)
            }
            .listRowBackground(Color.drift)
        }
        .scrollContentBackground(.hidden)
        .background(Color.snowfield)
        .accessibilityIdentifier("holdingsRoot")
        .navigationTitle("Bakiyelerim")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAdding) {
            HoldingEditorSheet(mode: .add)
        }
    }

    // MARK: - Toplam

    private var summary: some View {
        let accrued = state.holdings.reduce(Money(0)) { $0 + $1.accruedInterest }
        let nightly = state.holdings.reduce(Money(0)) { $0 + (state.nightlyNet(for: $1) ?? 0) }
        let pending = state.holdings.reduce(Money(0)) { $0 + state.pendingInterest(for: $1) }

        return VStack(spacing: 6) {
            Text(moneyText(state.totalHoldingsBalance))
                .font(dynamicTypeSize.isAccessibilitySize
                      ? .system(.largeTitle, design: .rounded).weight(.semibold)
                      : .system(size: heroSize, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospacedDigit()
                .foregroundStyle(.ink)
            Text("Toplam bakiye")
                .font(.subheadline)
                .foregroundStyle(.slate)
            if accrued > 0 {
                Text("\(HoldingText.signedMoney(accrued, locale: locale)) faiz eklendi")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.aurora)
                    .monospacedDigit()
            }
            if nightly > 0 {
                Text("Gecelik net kazanç ≈ \(moneyText(nightly))")
                    .font(.footnote)
                    .foregroundStyle(.slate)
                    .monospacedDigit()
            }
            if pending > 0 {
                Text("Hafta sonu biriken \(moneyText(pending)) Pazartesi eklenecek")
                    .font(.footnote)
                    .foregroundStyle(.slate)
                    .monospacedDigit()
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("holdingsTotal")
    }

    // MARK: - Kayıtlar

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Henüz bakiye yok")
                .font(.headline)
                .foregroundStyle(.ink)
            Text("Bankalardaki gerçek bakiyelerinizi ekleyin; uygulama her açılışta valörü gelen faizi üzerine ekler.")
                .font(.footnote)
                .foregroundStyle(.slate)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("holdingsEmpty")
    }

    private func row(_ holding: Holding) -> some View {
        let bank = state.bank(for: holding)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.displayName(for: holding))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                if let bank {
                    Text(HoldingText.rateCaption(for: bank, locale: locale))
                        .font(.caption)
                        .foregroundStyle(.slate)
                } else {
                    // Satır içi simge: Label'ın ikonu satır ayırıcısını içeri kaydırır.
                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) Banka Düzenle'de yok")
                        .font(.caption)
                        .foregroundStyle(.ember)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(moneyText(holding.balance))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if holding.accruedInterest > 0 {
                    Text(HoldingText.signedMoney(holding.accruedInterest, locale: locale))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.aurora)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func moneyText(_ value: Money) -> String {
        value.formatted(.currency(code: "TRY").locale(locale))
    }
}

#Preview {
    let state = AppState.preview
    state.addHolding(bankID: state.banks[0].id, balance: 100_000,
                     today: AccrualCalendar.addNights(-7, to: AccrualCalendar.today()))
    state.addHolding(bankID: state.banks[2].id, balance: 52_000)
    state.accrueHoldings()
    return NavigationStack {
        HoldingsScreen()
    }
    .environment(state)
}
