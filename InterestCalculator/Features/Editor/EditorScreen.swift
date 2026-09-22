//
//  EditorScreen.swift
//  InterestCalculator
//
//  Tab 2 — Düzenle. Form zemin reçetesi + beş bölüm + kademe listesi + yapışkan
//  canlı özet çubuğu. Gece sayısı BURADA DEĞİL (sonucu doğrudan değiştirdiği için
//  Tab 1'de).
//

import SwiftUI

struct EditorScreen: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: EditorField?

    private let withholdingNote = "Kanuni taban oran. Geçici kararlarla değişmiş olabilir; bankanızın ekstresinden veya güncel mevzuattan doğrulayın."

    var body: some View {
        @Bindable var state = state

        Form {
            Section("Para") {
                LabeledContent("Toplam tutar") {
                    DecimalTextField(unit: "₺", text: $state.balanceText,
                                     field: .balance, focused: $focused, kind: .money)
                }
            }
            .listRowBackground(Color.drift)

            Section {
                LabeledContent("Stopaj") {
                    DecimalTextField(unit: "%", text: $state.withholdingText,
                                     field: .withholding, focused: $focused, kind: .rate)
                }
            } header: {
                Text("Vergi")
            } footer: {
                Text(withholdingNote).foregroundStyle(.slate)
            }
            .listRowBackground(Color.drift)

            Section("Bankalar") {
                ForEach(state.banks) { bank in
                    Button {
                        state.selectedBankID = bank.id
                    } label: {
                        HStack {
                            Text(bank.name.isEmpty ? "Adsız banka" : bank.name)
                                .foregroundStyle(.ink)
                            Spacer()
                            if bank.id == state.selectedBank?.id {
                                Image(systemName: "checkmark").foregroundStyle(.glacier)
                            }
                        }
                    }
                }
                .onDelete { state.deleteBanks(at: $0) }

                Button { state.addBank() } label: {
                    Label("Banka ekle", systemImage: "plus")
                }
                .foregroundStyle(.glacier)
            }
            .listRowBackground(Color.drift)

            if let index = state.selectedBankIndex {
                Section("Seçili banka") {
                    LabeledContent("Ad") {
                        TextField("Banka adı", text: $state.banks[index].name)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.ink)
                    }
                    LabeledContent("Yıllık oran") {
                        DecimalTextField(unit: "%", text: $state.banks[index].annualRateText,
                                         field: .rate, focused: $focused, kind: .rate)
                    }
                    Picker("İlan tabanı", selection: $state.banks[index].rateBasis) {
                        Text("Brüt").tag(RateBasis.gross)
                        Text("Net").tag(RateBasis.net)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.drift)

                Section {
                    Picker("Şart türü", selection: $state.banks[index].idleKind) {
                        Text("Yok").tag(BankConditionDraft.IdleKind.none)
                        Text("Yüzde").tag(BankConditionDraft.IdleKind.percentage)
                        Text("Sabit tutar").tag(BankConditionDraft.IdleKind.fixedAmount)
                        Text("Kademeli").tag(BankConditionDraft.IdleKind.tiered)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: state.banks[index].idleKind) { _, newKind in
                        if newKind == .tiered { state.seedTiers(forBankAt: index) }
                    }

                    switch state.banks[index].idleKind {
                    case .none:
                        EmptyView()
                    case .percentage:
                        LabeledContent("Vadesiz yüzdesi") {
                            DecimalTextField(unit: "%", text: $state.banks[index].idlePercentageText,
                                             field: .idlePercentage, focused: $focused, kind: .rate)
                        }
                    case .fixedAmount:
                        LabeledContent("Vadesiz tutar") {
                            DecimalTextField(unit: "₺", text: $state.banks[index].idleFixedAmountText,
                                             field: .idleFixed, focused: $focused, kind: .money)
                        }
                    case .tiered:
                        ForEach($state.banks[index].tierDrafts) { $tier in
                            TierEditorRow(
                                tier: $tier,
                                isCatchAll: tier.id == state.banks[index].tierDrafts.last?.id,
                                isActive: tier.id == state.activeTierDraftID,
                                focused: $focused
                            )
                        }
                        .onDelete { state.deleteTiers(fromBankAt: index, at: $0) }

                        Button { state.addTier(toBankAt: index) } label: {
                            Label("Kademe ekle", systemImage: "plus")
                        }
                        .foregroundStyle(.glacier)
                    }
                } header: {
                    Text("Vadesiz kalma kuralı")
                } footer: {
                    tierFooter(state.banks[index])
                }
                .listRowBackground(Color.drift)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.snowfield)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { summaryBar }
        .accessibilityIdentifier("editorRoot")
    }

    @ViewBuilder
    private func tierFooter(_ draft: BankConditionDraft) -> some View {
        if draft.idleKind == .tiered {
            VStack(alignment: .leading, spacing: 4) {
                Text(TierSummaryText.summary(for: tierTable(for: draft)))
                Text("Kademeler, girdiğiniz üst sınıra göre değerlendirilir.")
            }
            .foregroundStyle(.slate)
        }
    }

    private func tierTable(for draft: BankConditionDraft) -> TierTable<TierRequirement> {
        if case .tiered(let table) = draft.makeCondition().idleRequirement {
            return table
        }
        return TierTable(normalizing: [], fallback: .fixedAmount(0))
    }

    private var summaryBar: some View {
        let net = state.result?.netInterest
        let netDouble = (net as NSDecimalNumber?)?.doubleValue ?? 0
        return HStack(spacing: 12) {
            Text("Net gecelik kazanç")
                .font(.subheadline)
                .foregroundStyle(.slate)
            Spacer()
            Group {
                if let net {
                    Text(net, format: .currency(code: "TRY"))
                        .contentTransition(.numericText(value: netDouble))
                } else {
                    Text("—")
                }
            }
            .font(.system(.title3, design: .rounded).weight(.medium))
            .foregroundStyle(.ink)
            .monospacedDigit()
            // .decimalPad'de Return yoktur; klavye açıkken "Bitti" burada.
            if focused != nil {
                Button("Bitti") { focused = nil }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.glacier)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(summaryBackground)
        .animation(reduceMotion ? nil : .default, value: netDouble)
    }

    private var summaryBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.drift) : AnyShapeStyle(.ultraThinMaterial)
    }
}

#Preview {
    EditorScreen()
        .environment(AppState.preview)
}
