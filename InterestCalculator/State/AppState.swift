//
//  AppState.swift
//  InterestCalculator
//
//  Tek sahiplik noktası. Ham String girdileri + motor çağrısı. Debounce/cache YOK.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    /// HAM metin — kaynağın doğrusu. Biçimlendirme Presentation'da.
    var balanceText: String = ""
    /// Stopaj yüzdesi, ön dolu "17.5" (kullanıcı düzenler; oran koda gömülmez).
    var withholdingText: String = "17.5"
    var nights: Int = 1
    var banks: [BankConditionDraft] = [.blankDefault]
    var selectedBankID: UUID?
    /// Aktif sekme — ekranlar arası geçiş (ör. boş durumdan Tab 2'ye) için.
    var selectedTab: AppTab = .summary

    init(loadPersisted: Bool = true) {
        guard loadPersisted, !Self.isUITesting, let snapshot = SessionStore.load() else { return }
        balanceText = snapshot.balanceText
        withholdingText = snapshot.withholdingText
        nights = snapshot.nights
        selectedBankID = snapshot.selectedBankID
        selectedTab = snapshot.selectedTab
        banks = snapshot.banks
    }

    /// Tüm oturumu UserDefaults'a yazar. Uygulama arka plana geçince çağrılır.
    func save() {
        guard !Self.isUITesting else { return }
        SessionStore.save(SessionSnapshot(
            balanceText: balanceText,
            withholdingText: withholdingText,
            nights: nights,
            selectedBankID: selectedBankID,
            selectedTab: selectedTab,
            banks: banks
        ))
    }

    /// UI testlerinde kalıcılık atlanır (boş-durum assert'leri deterministik kalsın).
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting")
    }

    /// Seçili banka; seçim geçersizse listenin ilkine düşer.
    var selectedBank: BankConditionDraft? {
        if let id = selectedBankID, let match = banks.first(where: { $0.id == id }) {
            return match
        }
        return banks.first
    }

    /// Canlı hesap sonucu. Bakiye ayrıştırılamıyorsa veya banka yoksa nil.
    var result: InterestResult? {
        guard let balance = DecimalInputParser.parse(balanceText),
              let draft = selectedBank else {
            return nil
        }
        let withholding: WithholdingRule = DecimalInputParser.parse(withholdingText)
            .map { .single(.percent($0)) } ?? .none
        return InterestEngine.calculate(
            InterestInput(
                totalBalance: balance,
                nights: nights,
                condition: draft.makeCondition(),
                withholding: withholding
            )
        )
    }

    /// Sonucu bloklayan (.error) tanılamalar.
    var blockingIssues: [CalculationDiagnostic] {
        result?.blockingIssues ?? []
    }

    /// Seçili bankanın `banks` içindeki indeksi (yazılabilir binding için).
    var selectedBankIndex: Int? {
        let targetID = selectedBankID ?? banks.first?.id
        guard let targetID else { return nil }
        return banks.firstIndex { $0.id == targetID }
    }

    /// Kademeli şartta mevcut bakiyenin düştüğü draft satırının id'si (canlı vurgu).
    /// Dışlayıcı sınır mantığı draft üzerinde, sıralı, tekrarlanır — motor
    /// normalizasyonundan bağımsız olarak tek satır döner.
    var activeTierDraftID: UUID? {
        guard let index = selectedBankIndex else { return nil }
        let draft = banks[index]
        guard draft.idleKind == .tiered, !draft.tierDrafts.isEmpty,
              let balance = DecimalInputParser.parse(balanceText) else { return nil }
        let sorted = draft.tierDrafts.sorted { lhs, rhs in
            switch (DecimalInputParser.parse(lhs.upperBoundText), DecimalInputParser.parse(rhs.upperBoundText)) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
        for tier in sorted {
            let bound = DecimalInputParser.parse(tier.upperBoundText)
            if bound == nil || balance < bound! { return tier.id }
        }
        return sorted.last?.id
    }

    // MARK: - Mutasyonlar

    func addBank() {
        let draft = BankConditionDraft.blankDefault
        banks.append(draft)
        selectedBankID = draft.id
    }

    func deleteBanks(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where banks.indices.contains(index) {
            banks.remove(at: index)
        }
        if let id = selectedBankID, banks.contains(where: { $0.id == id }) == false {
            selectedBankID = banks.first?.id
        }
    }

    /// Kademeli şarta ilk geçişte örnek yapıyı doldur (uçurum örneği).
    func seedTiers(forBankAt index: Int) {
        guard banks.indices.contains(index), banks[index].tierDrafts.isEmpty else { return }
        banks[index].tierDrafts = [
            .init(upperBoundText: "50.000", amountText: "5.000"),
            .init(upperBoundText: "", amountText: "10.000"),   // "ve üzeri" yakalayıcı
        ]
    }

    /// Yeni kademeyi "ve üzeri" yakalayıcının HEMEN ÖNÜNE, akıllı varsayılanla
    /// (önceki üst sınırın 2 katı) ekler.
    func addTier(toBankAt index: Int) {
        guard banks.indices.contains(index) else { return }
        var tiers = banks[index].tierDrafts
        if tiers.isEmpty {
            tiers = [.init(upperBoundText: "", amountText: "")]
        } else {
            let insertAt = tiers.count - 1
            let previousBound = insertAt > 0 ? DecimalInputParser.parse(tiers[insertAt - 1].upperBoundText) : nil
            let boundText = (previousBound.map { $0 * 2 })?.grouped(fractionDigits: 0) ?? "50.000"
            tiers.insert(.init(upperBoundText: boundText, amountText: ""), at: insertAt)
        }
        banks[index].tierDrafts = tiers
    }

    func deleteTiers(fromBankAt index: Int, at offsets: IndexSet) {
        guard banks.indices.contains(index) else { return }
        for tierIndex in offsets.sorted(by: >) where banks[index].tierDrafts.indices.contains(tierIndex) {
            banks[index].tierDrafts.remove(at: tierIndex)
        }
    }

    /// Önizleme fixture'ı — her #Preview bununla sarılır, yoksa @Environment crash eder.
    static var preview: AppState {
        let state = AppState(loadPersisted: false)
        state.balanceText = "100.000"
        state.withholdingText = "17.5"
        state.nights = 1
        state.banks = [.sample]
        state.selectedBankID = state.banks.first?.id
        return state
    }
}
