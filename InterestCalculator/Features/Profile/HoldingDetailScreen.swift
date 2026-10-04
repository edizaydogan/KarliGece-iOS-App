//
//  HoldingDetailScreen.swift
//  InterestCalculator
//
//  Bakiyelerim'deki bir kaydın detayı: valörlenmiş bakiye, girilen bakiye ve
//  o günden bu yana eklenen faiz, gecelik net kazanç, hafta sonu bekleyen
//  kazanç ve hareketler (giriş + her valör gününün faizi). "Düzenle" bankayı
//  ya da bakiyeyi değiştirir; "Kaydı sil" onay ister.
//

import SwiftUI

struct HoldingDetailScreen: View {
    let holdingID: UUID
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 36
    @State private var isEditing = false
    @State private var confirmsDelete = false
    /// Son görülen kayıt: silindikten sonra geri dönüş animasyonu boyunca
    /// içerik boşalmasın.
    @State private var lastSeen: Holding?

    private var holding: Holding? {
        state.holdings.first { $0.id == holdingID } ?? lastSeen
    }

    var body: some View {
        Group {
            if let holding {
                content(holding)
            } else {
                Color.snowfield.ignoresSafeArea()
            }
        }
        .navigationTitle(holding.map { state.displayName(for: $0) } ?? locale.localized("Bakiye"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Düzenle") { isEditing = true }
                    .accessibilityIdentifier("holdingEditButton")
            }
        }
        .sheet(isPresented: $isEditing) {
            HoldingEditorSheet(mode: .edit(holdingID))
        }
        .onAppear {
            lastSeen = state.holdings.first { $0.id == holdingID }
        }
        .onChange(of: state.holdings) { _, holdings in
            if let current = holdings.first(where: { $0.id == holdingID }) {
                lastSeen = current
            }
        }
    }

    private func content(_ holding: Holding) -> some View {
        let bank = state.bank(for: holding)
        let pending = state.pendingInterest(for: holding)

        return List {
            Section {
                hero(holding, bank: bank)
            }
            .listRowBackground(Color.drift)

            if bank == nil {
                Section {
                    Label("Bu kaydın bankası Düzenle sekmesinde yok; faiz eklenmiyor. Sağ üstteki Düzenle ile başka bir banka seçebilirsiniz.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.ember)
                }
                .listRowBackground(Color.drift)
            }

            Section("Özet") {
                valueRow("Girilen bakiye", moneyText(holding.enteredBalance),
                         caption: HoldingText.dayText(holding.enteredOn, locale: locale))
                valueRow("Eklenen faiz", HoldingText.signedMoney(holding.accruedInterest, locale: locale),
                         color: holding.accruedInterest > 0 ? .aurora : .ink)
                if let nightly = state.nightlyNet(for: holding) {
                    valueRow("Gecelik net kazanç", "≈ " + moneyText(nightly))
                }
                if pending > 0 {
                    valueRow("Pazartesi eklenecek", "≈ " + moneyText(pending),
                             caption: locale.localized("Cuma–Pazar kazancı Pazartesi 00:00'da eklenir"))
                }
            }
            .listRowBackground(Color.drift)

            Section {
                ForEach(holding.entries) { entry in
                    entryRow(entry)
                }
            } header: {
                Text("Hareketler")
            } footer: {
                if holding.entries.count >= HoldingLedger.entryLimit {
                    Text("Son \(HoldingLedger.entryLimit) hareket gösterilir.").foregroundStyle(.slate)
                }
            }
            .listRowBackground(Color.drift)

            Section {
                Button("Kaydı sil", role: .destructive) { confirmsDelete = true }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("holdingDeleteButton")
                    .confirmationDialog("Bakiye kaydı silinsin mi?", isPresented: $confirmsDelete,
                                        titleVisibility: .visible) {
                        Button("Kaydı Sil", role: .destructive) {
                            dismiss()
                            state.deleteHolding(holdingID)
                        }
                        Button("Vazgeç", role: .cancel) {}
                    } message: {
                        Text("Bakiye ve hareketleri silinir. Bu işlem geri alınamaz.")
                    }
            }
            .listRowBackground(Color.drift)
        }
        .scrollContentBackground(.hidden)
        .background(Color.snowfield)
        .accessibilityIdentifier("holdingDetailRoot")
    }

    // MARK: - Parçalar

    private func hero(_ holding: Holding, bank: BankConditionDraft?) -> some View {
        VStack(spacing: 6) {
            Text(moneyText(holding.balance))
                .font(dynamicTypeSize.isAccessibilitySize
                      ? .system(.largeTitle, design: .rounded).weight(.semibold)
                      : .system(size: heroSize, weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospacedDigit()
                .foregroundStyle(.ink)
            Text(bank.map { HoldingText.conditionSummary(for: $0, withholdingText: state.withholdingText, locale: locale) }
                 ?? locale.localized("Faiz işlemiyor"))
                .font(.subheadline)
                .foregroundStyle(.slate)
            Text("\(HoldingText.dayText(holding.asOf, locale: locale)) itibarıyla")
                .font(.footnote)
                .foregroundStyle(.slate)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("holdingDetailBalance")
    }

    @ViewBuilder
    private func valueRow(_ label: LocalizedStringKey, _ value: String, caption: String? = nil,
                          color: Color = .ink) -> some View {
        let labelView = VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(.slate)
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.slate)
            }
        }
        let valueText = Text(value)
            .font(.system(.body, design: .rounded).weight(.medium))
            .foregroundStyle(color)
            .monospacedDigit()

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) { labelView; valueText }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        } else {
            HStack(alignment: .firstTextBaseline) { labelView; Spacer(minLength: 8); valueText }
                .accessibilityElement(children: .combine)
        }
    }

    private func entryRow(_ entry: HoldingEntry) -> some View {
        let isInterest = entry.kind != .balanceSet
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HoldingText.title(for: entry, locale: locale))
                    .foregroundStyle(.ink)
                Text(HoldingText.dayText(entry.day, locale: locale))
                    .font(.caption)
                    .foregroundStyle(.slate)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if isInterest {
                    Text(HoldingText.signedMoney(entry.change, locale: locale))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(.aurora)
                    Text(moneyText(entry.balanceAfter))
                        .font(.caption)
                        .foregroundStyle(.slate)
                } else {
                    Text(moneyText(entry.balanceAfter))
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(.ink)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func moneyText(_ value: Money) -> String {
        value.formatted(.currency(code: "TRY").locale(locale))
    }
}

#Preview {
    let state = AppState.preview
    let id = state.addHolding(bankID: state.banks[0].id, balance: 100_000,
                              today: AccrualCalendar.addNights(-9, to: AccrualCalendar.today()))
    state.accrueHoldings()
    return NavigationStack {
        HoldingDetailScreen(holdingID: id ?? UUID())
    }
    .environment(state)
}
