//
//  HoldingEditorSheet.swift
//  InterestCalculator
//
//  Bakiyelerim'e kayıt ekleme ve kaydı düzenleme sayfası: banka (Düzenle'deki
//  bankalardan, her bankada bir kayıt) ve bankadaki güncel bakiye. Bakiye
//  kaydedildiği gün itibarıyla geçerlidir; düzenlemede yalnız tutar
//  değişirse "eklenen faiz" sıfırlanır.
//

import SwiftUI

struct HoldingEditorSheet: View {
    enum Mode: Hashable {
        case add
        case edit(UUID)
    }

    let mode: Mode
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: EditorField?
    @State private var bankID: UUID?
    @State private var balanceText = ""
    @State private var isSeeded = false

    private var isAdding: Bool { mode == .add }

    private var editing: Holding? {
        guard case .edit(let id) = mode else { return nil }
        return state.holdings.first { $0.id == id }
    }

    /// Seçilebilir bankalar: bakiyesi girilmemiş olanlar ve düzenlenen kaydın kendi bankası.
    private var options: [BankConditionDraft] {
        state.banks.filter { bank in
            bank.id == editing?.bankID || !state.holdings.contains { $0.bankID == bank.id }
        }
    }

    private var selectedBank: BankConditionDraft? {
        options.first { $0.id == bankID }
    }

    private var parsedBalance: Money? {
        guard let value = DecimalInputParser.parse(balanceText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.isEmpty {
                    noBankSection
                } else {
                    Section {
                        Picker("Banka", selection: $bankID) {
                            if selectedBank == nil {
                                Text("Seçin").tag(UUID?.none)
                            }
                            ForEach(options) { bank in
                                Text(state.displayName(for: bank)).tag(UUID?.some(bank.id))
                            }
                        }
                        .accessibilityIdentifier("holdingBankPicker")
                        LabeledContent("Güncel bakiye") {
                            DecimalTextField(unit: "₺", text: $balanceText, field: .holdingBalance,
                                             focused: $focused, kind: .money,
                                             identifier: "holdingBalanceField")
                        }
                    } footer: {
                        footer
                    }
                    .listRowBackground(Color.drift)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.snowfield)
            .scrollDismissesKeyboard(.interactively)
            .tint(.glacier)
            .navigationTitle(isAdding ? "Bakiye ekle" : "Bakiyeyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Ekle" : "Kaydet", action: save)
                        .fontWeight(.semibold)
                        .disabled(selectedBank == nil || parsedBalance == nil)
                        .accessibilityIdentifier("holdingSaveButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if focused != nil {
                        Spacer()
                        Button("Bitti") { focused = nil }
                    }
                }
            }
            .onAppear(perform: seed)
        }
    }

    // MARK: - Bölümler

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bankanızdaki güncel bakiyeyi girin. Uygulama her açılışta valörü gelen net faizi bu bakiyeye ekler: hafta içi kazanç ertesi gün, Cuma–Pazar kazancı Pazartesi.")
            if let bank = selectedBank {
                Text("Faiz Düzenle'deki koşullarla işler: \(HoldingText.conditionSummary(for: bank, withholdingText: state.withholdingText)).")
                if (DecimalInputParser.parse(bank.annualRateText) ?? 0) <= 0 {
                    Text("Bu bankanın oranı girilmemiş; faiz eklenmez.")
                        .foregroundStyle(.ember)
                }
            }
            if !isAdding {
                Text("Bakiyeyi değiştirirseniz yeni tutar bugün itibarıyla geçerli olur ve eklenen faiz sıfırlanır.")
            }
        }
        .foregroundStyle(.slate)
    }

    private var noBankSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(state.banks.isEmpty
                     ? "Bakiye bir bankaya bağlanır ve o bankanın koşullarıyla faiz alır. Önce Düzenle'den banka ekleyin."
                     : "Tüm bankaların bakiyesi girilmiş; her bankada bir kayıt tutulur. Yeni banka Düzenle'den eklenir.")
                    .font(.subheadline)
                    .foregroundStyle(.ink)
                Button("Düzenle'ye git") {
                    dismiss()
                    state.selectedTab = .editor
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("holdingGoToEditorButton")
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.drift)
    }

    // MARK: - Eylemler

    /// Alanları bir kez doldurur; sonraki görünüşler kullanıcının girdisini ezmez.
    private func seed() {
        guard !isSeeded else { return }
        isSeeded = true
        if let editing {
            bankID = options.contains { $0.id == editing.bankID } ? editing.bankID : nil
            balanceText = editing.balance.grouped(fractionDigits: 2)
        } else {
            // Özet'te seçili banka uygunsa o, değilse ilk uygun banka.
            let preferred = state.selectedBank?.id
            bankID = options.contains { $0.id == preferred } ? preferred : options.first?.id
        }
    }

    private func save() {
        guard let bank = selectedBank, let balance = parsedBalance else { return }
        focused = nil
        switch mode {
        case .add:
            state.addHolding(bankID: bank.id, balance: balance)
        case .edit(let id):
            state.updateHolding(id, bankID: bank.id, balance: balance)
        }
        dismiss()
    }
}

#Preview {
    HoldingEditorSheet(mode: .add)
        .environment(AppState.preview)
}
