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
    /// Vade uzunluğu = gece sayısı. DAİMA normalize (bitiş hafta sonuna düşmez).
    var nights: Int = 1
    /// Vade başlangıcı. DAİMA bugüne düşer (kalıcı değildir; her açılışta bugün).
    /// Valör/hafta günü kuralı bu tarihin gününden yürür.
    var startDate: Date = AccrualCalendar.today()
    var banks: [BankConditionDraft] = [.blankDefault]
    var selectedBankID: UUID?
    /// Aktif sekme — ekranlar arası geçiş (ör. boş durumdan Tab 2'ye) için.
    var selectedTab: AppTab = .summary
    /// Max geçmişi, en yeni başta; en fazla `maxHistoryLimit` kayıt. Oturumla
    /// birlikte kaydedilir.
    var maxHistory: [MaxPlanRecord] = []

    static let maxHistoryLimit = 50

    init(loadPersisted: Bool = true) {
        guard loadPersisted, !Self.isUITesting, let snapshot = SessionStore.load() else { return }
        balanceText = snapshot.balanceText
        withholdingText = snapshot.withholdingText
        selectedBankID = snapshot.selectedBankID
        selectedTab = snapshot.selectedTab
        banks = snapshot.banks
        maxHistory = snapshot.maxHistory ?? []
        // Başlangıç DAİMA bugün; kayıtlı gün sayısı bugünün gününe göre yeniden
        // normalize edilir (bitiş hafta sonuna düşmesin).
        nights = AccrualCalendar.normalizedNights(start: startDate, requested: snapshot.nights)
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
            banks: banks,
            maxHistory: maxHistory
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

    /// Vade bitiş tarihi = başlangıç + gün sayısı (gün sayısı normalize olduğu
    /// için bitiş daima iş günüdür).
    var endDate: Date {
        AccrualCalendar.endDate(start: startDate, nights: nights)
    }

    /// Ayrıştırılmış toplam tutar (Düzenle'deki); metin geçersizse nil. Karşılaştır
    /// ve Max bunu kullanmaz: kendi yerel tutarları vardır, `balanceText`'i yalnız
    /// tohum olarak okur ve hiç yazmaz.
    var parsedBalance: Money? {
        DecimalInputParser.parse(balanceText)
    }

    /// Stopaj kuralı; metin ayrıştırılamıyorsa stopajsız.
    var withholdingRule: WithholdingRule {
        DecimalInputParser.parse(withholdingText).map { .single(.percent($0)) } ?? .none
    }

    /// Canlı hesap sonucu. Bakiye ayrıştırılamıyorsa veya banka yoksa nil.
    /// Özet artık valör kurallı BİLEŞİK sonuç gösterir: net kazanç ertesi gün
    /// (hafta sonu Pazartesi) valörüyle bakiyeye eklenip sonraki geceyi büyütür.
    var result: InterestResult? {
        guard let balance = parsedBalance,
              let draft = selectedBank else {
            return nil
        }
        return CompoundingEngine.project(
            initialBalance: balance,
            startWeekday: AccrualCalendar.weekday(for: startDate),
            nights: nights,
            condition: draft.makeCondition(),
            withholding: withholdingRule
        )
    }

    /// Bankanın gösterim adı. Adsızsa listedeki sırasıyla "Adsız banka N" —
    /// Karşılaştır menüsünde birden çok adsız banka ayırt edilebilsin.
    func displayName(for bank: BankConditionDraft) -> String {
        if !bank.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bank.name
        }
        let position = (banks.firstIndex { $0.id == bank.id } ?? 0) + 1
        return "Adsız banka \(position)"
    }

    /// Max planlayıcının girdisi: kayıtlı bankaların motor koşulları, adları
    /// gösterim adıyla ("Adsız banka N") — plan ve geçmiş bu adları taşır.
    var planningConditions: [BankCondition] {
        banks.map { draft in
            var condition = draft.makeCondition()
            condition.name = displayName(for: draft)
            return condition
        }
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

    // MARK: - Vade mutasyonları (takvim ↔ gün sayısı, hep normalize)

    /// Kullanıcı gün sayısını doğrudan girdi (ör. 10). Bitiş hafta sonuna
    /// düşerse Pazartesi'ye çekilir; gün sayısı gerçek aralığa göre güncellenir.
    func setDayCount(_ requested: Int) {
        nights = AccrualCalendar.normalizedNights(start: startDate, requested: requested)
    }

    /// Adım "+": bitişi bir sonraki iş gününe taşır (hafta sonunu ileri atlar,
    /// Cuma → Pazartesi).
    func incrementDayCount() {
        nights = AccrualCalendar.nextBusinessNights(start: startDate, after: nights)
    }

    /// Adım "−": bitişi bir önceki iş gününe taşır (hafta sonunu GERİ atlar,
    /// Pazartesi → Cuma). Daha küçük geçerli vade yoksa değişmez.
    func decrementDayCount() {
        if let previous = AccrualCalendar.previousBusinessNights(start: startDate, before: nights) {
            nights = previous
        }
    }

    /// Kullanıcı takvimden bir bitiş günü seçti. Hafta sonuysa Pazartesi'ye
    /// çekilir; gün sayısı buna göre türetilir.
    func setEndDate(_ date: Date) {
        let snapped = AccrualCalendar.snappedOffWeekend(date)
        nights = max(1, AccrualCalendar.nights(from: startDate, to: snapped))
    }

    /// Kullanıcı başlangıç gününü değiştirdi. Gün sayısı korunur ama yeni
    /// başlangıca göre yeniden normalize edilir.
    func setStartDate(_ date: Date) {
        startDate = AccrualCalendar.startOfDay(date)
        nights = AccrualCalendar.normalizedNights(start: startDate, requested: nights)
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

    /// Yeni Max planını geçmişin başına ekler; sınırı aşan en eski kayıtlar düşer.
    /// Kalıcılık oturumun geri kalanıyla aynı: uygulama etkin olmaktan çıkınca.
    func recordMaxPlan(_ record: MaxPlanRecord) {
        maxHistory.insert(record, at: 0)
        if maxHistory.count > Self.maxHistoryLimit {
            maxHistory.removeLast(maxHistory.count - Self.maxHistoryLimit)
        }
    }

    /// Önizleme fixture'ı — her #Preview bununla sarılır, yoksa @Environment crash eder.
    static var preview: AppState {
        let state = AppState(loadPersisted: false)
        state.balanceText = "100.000"
        state.withholdingText = "17.5"
        state.nights = 1
        // İlk (ve seçili) banka `.sample` — Özet önizlemesi değişmez; diğer ikisi
        // Karşılaştır'ın üç sütununu doldurur.
        state.banks = [.sample, .sampleFlat, .sampleNet]
        state.selectedBankID = state.banks.first?.id
        return state
    }
}
