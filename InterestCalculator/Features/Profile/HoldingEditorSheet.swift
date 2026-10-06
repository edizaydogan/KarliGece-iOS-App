//
//  HoldingEditorSheet.swift
//  InterestCalculator
//
//  Bakiyelerim'e kayıt ekleme ve kaydı düzenleme sayfası: banka (Düzenle'deki
//  bankalardan, her bankada bir kayıt), bankadaki güncel bakiye ve faizin nasıl
//  işleyeceği. Güncel bakiyenin altında iki seçim vardır: bankanın hafta sonu
//  faizi (1 gecelik / 3 gecelik, kayıtla saklanır) ve "Bugünün faizini
//  kaçırdım" (telefonun bugününün faiz bloğunu, 1 geceyi ya da Cuma–Pazar'ın 3
//  gecesini atlar). Altlarındaki satır ilk faizin hangi gün ve kaç gece
//  ekleneceğini canlı gösterir. Bakiye kaydedildiği gün itibarıyla geçerlidir;
//  düzenlemede tutar ya da "bugünün faizi" seçimi değişirse "eklenen faiz"
//  sıfırlanır.
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
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: EditorField?
    @State private var bankID: UUID?
    @State private var balanceText = ""
    @State private var weekendInterest: WeekendInterest = .threeNights
    @State private var missesTodaysInterest = false
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

    /// Telefonun tarihine göre bugün: seçimler bu günün faiz bloğuna uygulanır.
    private var today: CalendarDay {
        AccrualCalendar.day(for: Date())
    }

    /// Kaydedilirse faizin ilk (düzenlemede bir sonraki) ekleneceği gün ve gece
    /// sayısı. Kaydetmeyle aynı defter adımları bir kopya üzerinde yürütülür.
    private var nextCredit: HoldingLedger.Credit {
        let day = today
        if var holding = editing {
            HoldingLedger.edit(&holding, balance: parsedBalance ?? holding.balance,
                               weekendInterest: weekendInterest,
                               missesTodaysInterest: missesTodaysInterest, on: day)
            return HoldingLedger.nextCredit(holding, after: day)
        }
        let holding = HoldingLedger.open(bankID: UUID(), bankName: "", balance: parsedBalance ?? 0, on: day,
                                         weekendInterest: weekendInterest,
                                         missesTodaysInterest: missesTodaysInterest)
        return HoldingLedger.nextCredit(holding, after: day)
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
                        weekendInterestRow
                        missedTodayRow
                        LabeledContent(isAdding ? "İlk faiz" : "Sonraki faiz") {
                            Text(HoldingText.creditText(nextCredit, locale: locale))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("holdingNextCredit")
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

    /// Bankanın hafta sonu faizi: iki seçenekli düğme. Erişilebilirlik
    /// boyutlarında başlık seçicinin üstüne iner.
    @ViewBuilder
    private var weekendInterestRow: some View {
        let picker = Picker("Hafta sonu faizi", selection: $weekendInterest) {
            Text("1 gecelik").tag(WeekendInterest.oneNight)
            Text("3 gecelik").tag(WeekendInterest.threeNights)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("holdingWeekendPicker")

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hafta sonu faizi").foregroundStyle(.ink)
                picker
            }
        } else {
            LabeledContent("Hafta sonu faizi") {
                picker.fixedSize()
            }
        }
    }

    /// "Bugünün faizini kaçırdım": bugünün bloğu 1 gece mi 3 gece mi, altında yazar.
    private var missedTodayRow: some View {
        let nights = HoldingLedger.todaysInterestNights(on: today, weekendInterest: weekendInterest)
        return Toggle(isOn: $missesTodaysInterest) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bugünün faizini kaçırdım")
                    .foregroundStyle(.ink)
                Text(nights == 1 ? "Bu gecenin faizi (1 gece) atlanır." : "Cuma–Pazar faizi (3 gece) atlanır.")
                    .font(.caption)
                    .foregroundStyle(.slate)
            }
        }
        .toggleStyle(CheckboxRowStyle())
        .accessibilityIdentifier("holdingMissedTodayToggle")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bankanızdaki güncel bakiyeyi girin. Uygulama her açılışta valörü gelen net faizi bu bakiyeye ekler; hafta içi kazanç ertesi gün eklenir.")
            Text(weekendInterest == .oneNight
                 ? "1 gecelik: hafta sonu da her gece faiz işler, kazanç ertesi gün eklenir."
                 : "3 gecelik: Cuma, Cumartesi ve Pazar geceleri Cuma bakiyesi üzerinden işler, toplamı Pazartesi eklenir.")
            if let bank = selectedBank {
                Text("Faiz Düzenle'deki koşullarla işler: \(HoldingText.conditionSummary(for: bank, withholdingText: state.withholdingText, locale: locale)).")
                if (DecimalInputParser.parse(bank.annualRateText) ?? 0) <= 0 {
                    Text("Bu bankanın oranı girilmemiş; faiz eklenmez.")
                        .foregroundStyle(.ember)
                }
            }
            if !isAdding {
                Text("Bakiyeyi ya da bugünün faizi seçimini değiştirirseniz bakiye bugün itibarıyla yeniden girilir ve eklenen faiz sıfırlanır. Yalnız hafta sonu faizini değiştirmek bakiyeyi korur.")
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
            balanceText = editing.balance.grouped(fractionDigits: 2, locale: locale)
            weekendInterest = editing.weekendInterest
            missesTodaysInterest = HoldingLedger.missesTodaysInterest(editing, on: today)
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
            state.addHolding(bankID: bank.id, balance: balance, weekendInterest: weekendInterest,
                             missesTodaysInterest: missesTodaysInterest)
        case .edit(let id):
            state.updateHolding(id, bankID: bank.id, balance: balance, weekendInterest: weekendInterest,
                                missesTodaysInterest: missesTodaysInterest)
        }
        dismiss()
    }
}

#Preview {
    HoldingEditorSheet(mode: .add)
        .environment(AppState.preview)
}
