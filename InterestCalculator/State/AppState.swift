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
    /// Profil bilgileri (ad, soyad).
    var profile = UserProfile()
    /// Renk düzeni tercihi; `.system` cihazı izler.
    var appearance: AppAppearance = .system
    /// Arayüz dili; kök görünüm `\.locale` ortamına verir. Cihaz dilinden
    /// bağımsızdır, varsayılan Türkçe.
    var language: AppLanguage = .turkish
    /// Profil → Bakiyelerim: bankalardaki gerçek bakiyeler, Düzenle'deki sırayla
    /// değil eklenme sırasıyla. Her açılışta valörü gelen faiz eklenir
    /// (`accrueHoldings`); oturumla birlikte kaydedilir.
    var holdings: [Holding] = []

    static let maxHistoryLimit = 50

    init(loadPersisted: Bool = true) {
        guard loadPersisted, !Self.isUITesting, let snapshot = SessionStore.load() else {
            debugPrint("[AppState] Kayıtlı oturum kullanılmadı, uygulama varsayılan durumla başladı.")
            return
        }
        balanceText = snapshot.balanceText
        withholdingText = snapshot.withholdingText
        selectedBankID = snapshot.selectedBankID
        selectedTab = snapshot.selectedTab
        banks = snapshot.banks
        maxHistory = snapshot.maxHistory ?? []
        profile = snapshot.profile ?? UserProfile()
        appearance = snapshot.appearance ?? .system
        language = snapshot.language ?? .turkish
        holdings = snapshot.holdings ?? []
        // Başlangıç DAİMA bugün; kayıtlı gün sayısı bugünün gününe göre yeniden
        // normalize edilir (bitiş hafta sonuna düşmesin).
        nights = AccrualCalendar.normalizedNights(start: startDate, requested: snapshot.nights)
        debugPrint("[AppState] Kayıtlı oturum geri yüklendi: \(banks.count) banka, \(maxHistory.count) Max kaydı, \(holdings.count) bakiye, vade \(snapshot.nights) → \(nights) gece.")
        // Uygulama açılışı: son açılıştan bu yana valörü gelen faiz eklenir.
        accrueHoldings()
    }

    /// Tüm oturumu UserDefaults'a yazar. Uygulama arka plana geçince çağrılır.
    func save() {
        guard !Self.isUITesting else {
            debugPrint("[AppState] UI testi çalıştığı için oturum kaydı atlandı.")
            return
        }
        SessionStore.save(SessionSnapshot(
            balanceText: balanceText,
            withholdingText: withholdingText,
            nights: nights,
            selectedBankID: selectedBankID,
            selectedTab: selectedTab,
            banks: banks,
            maxHistory: maxHistory,
            profile: profile,
            appearance: appearance,
            language: language,
            holdings: holdings
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
        let projected = CompoundingEngine.project(
            initialBalance: balance,
            startWeekday: AccrualCalendar.weekday(for: startDate),
            nights: nights,
            condition: draft.makeCondition(),
            withholding: withholdingRule
        )
        debugPrint("[AppState] Özet sonucu hesaplandı: \(displayName(for: draft)), \(balance) ₺, \(nights) gece, net \(projected.netInterest) ₺.")
        return projected
    }

    /// Bankanın gösterim adı. Adsızsa listedeki sırasıyla "Adsız banka N"
    /// (seçilen dilde) — Karşılaştır menüsünde birden çok adsız banka ayırt
    /// edilebilsin.
    func displayName(for bank: BankConditionDraft) -> String {
        if !bank.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bank.name
        }
        let position = (banks.firstIndex { $0.id == bank.id } ?? 0) + 1
        return language.locale.localized("Adsız banka \(position)")
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

    /// Max planlayıcının EFT ücretleri, banka id'siyle (motor koşulu EFT taşımaz).
    var planningEftFees: [UUID: Money] {
        Dictionary(banks.map { ($0.id, $0.eftFee) }, uniquingKeysWith: { first, _ in first })
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
        debugPrint("[AppState] Gün sayısı \(requested) girildi, vade \(nights) gece olarak ayarlandı.")
    }

    /// Adım "+": bitişi bir sonraki iş gününe taşır (hafta sonunu ileri atlar,
    /// Cuma → Pazartesi).
    func incrementDayCount() {
        nights = AccrualCalendar.nextBusinessNights(start: startDate, after: nights)
        debugPrint("[AppState] Vade bir sonraki iş gününe uzatıldı: \(nights) gece.")
    }

    /// Adım "−": bitişi bir önceki iş gününe taşır (hafta sonunu GERİ atlar,
    /// Pazartesi → Cuma). Daha küçük geçerli vade yoksa değişmez.
    func decrementDayCount() {
        if let previous = AccrualCalendar.previousBusinessNights(start: startDate, before: nights) {
            nights = previous
            debugPrint("[AppState] Vade bir önceki iş gününe kısaltıldı: \(nights) gece.")
        } else {
            debugPrint("[AppState] Daha kısa geçerli vade olmadığı için vade \(nights) gecede kaldı.")
        }
    }

    /// Kullanıcı takvimden bir bitiş günü seçti. Hafta sonuysa Pazartesi'ye
    /// çekilir; gün sayısı buna göre türetilir.
    func setEndDate(_ date: Date) {
        let snapped = AccrualCalendar.snappedOffWeekend(date)
        nights = max(1, AccrualCalendar.nights(from: startDate, to: snapped))
        debugPrint("[AppState] Bitiş tarihi \(snapped.formatted(date: .numeric, time: .omitted)) olarak ayarlandı, vade \(nights) gece.")
    }

    /// Kullanıcı başlangıç gününü değiştirdi. Gün sayısı korunur ama yeni
    /// başlangıca göre yeniden normalize edilir.
    func setStartDate(_ date: Date) {
        startDate = AccrualCalendar.startOfDay(date)
        nights = AccrualCalendar.normalizedNights(start: startDate, requested: nights)
        debugPrint("[AppState] Başlangıç tarihi \(startDate.formatted(date: .numeric, time: .omitted)) olarak ayarlandı, vade \(nights) geceye yeniden normalize edildi.")
    }

    // MARK: - Mutasyonlar

    func addBank() {
        let draft = BankConditionDraft.blankDefault
        banks.append(draft)
        selectedBankID = draft.id
        debugPrint("[AppState] Yeni boş banka eklendi ve seçildi, toplam \(banks.count) banka.")
    }

    func deleteBanks(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where banks.indices.contains(index) {
            banks.remove(at: index)
        }
        if let id = selectedBankID, banks.contains(where: { $0.id == id }) == false {
            selectedBankID = banks.first?.id
        }
        debugPrint("[AppState] \(offsets.count) banka silindi, kalan \(banks.count) banka.")
    }

    /// Kademeli şarta ilk geçişte örnek yapıyı doldur (uçurum örneği).
    func seedTiers(forBankAt index: Int) {
        guard banks.indices.contains(index), banks[index].tierDrafts.isEmpty else { return }
        let locale = language.locale
        banks[index].tierDrafts = [
            .init(upperBoundText: Decimal(50_000).grouped(fractionDigits: 0, locale: locale),
                  amountText: Decimal(5_000).grouped(fractionDigits: 0, locale: locale)),
            // "ve üzeri" yakalayıcı
            .init(upperBoundText: "", amountText: Decimal(10_000).grouped(fractionDigits: 0, locale: locale)),
        ]
        debugPrint("[AppState] Kademeli şart için örnek kademeler dolduruldu: \(displayName(for: banks[index])).")
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
            let boundText = (previousBound.map { $0 * 2 } ?? 50_000).grouped(fractionDigits: 0, locale: language.locale)
            tiers.insert(.init(upperBoundText: boundText, amountText: ""), at: insertAt)
        }
        banks[index].tierDrafts = tiers
        debugPrint("[AppState] Kademe eklendi: \(displayName(for: banks[index])), toplam \(tiers.count) kademe.")
    }

    func deleteTiers(fromBankAt index: Int, at offsets: IndexSet) {
        guard banks.indices.contains(index) else { return }
        for tierIndex in offsets.sorted(by: >) where banks[index].tierDrafts.indices.contains(tierIndex) {
            banks[index].tierDrafts.remove(at: tierIndex)
        }
        debugPrint("[AppState] \(offsets.count) kademe silindi: \(displayName(for: banks[index])), kalan \(banks[index].tierDrafts.count) kademe.")
    }

    /// Yeni Max planını geçmişin başına ekler; sınırı aşan en eski kayıtlar düşer.
    /// Kalıcılık oturumun geri kalanıyla aynı: uygulama etkin olmaktan çıkınca.
    func recordMaxPlan(_ record: MaxPlanRecord) {
        maxHistory.insert(record, at: 0)
        if maxHistory.count > Self.maxHistoryLimit {
            maxHistory.removeLast(maxHistory.count - Self.maxHistoryLimit)
        }
        debugPrint("[AppState] Max planı geçmişin başına eklendi, geçmişte \(maxHistory.count) kayıt var.")
    }

    /// Max geçmişini tümüyle siler (geri alınamaz; onayı ekran ister).
    func clearMaxHistory() {
        let removed = maxHistory.count
        maxHistory.removeAll()
        debugPrint("[AppState] Max geçmişi temizlendi, \(removed) kayıt silindi.")
    }

    // MARK: - Profil → Bakiyelerim

    /// Kaydın bağlı olduğu banka; Düzenle'den silinmişse nil (faiz işlemez).
    func bank(for holding: Holding) -> BankConditionDraft? {
        banks.first { $0.id == holding.bankID }
    }

    /// Kaydın gösterim adı: banka duruyorsa güncel adı, silinmişse son bilinen adı.
    func displayName(for holding: Holding) -> String {
        bank(for: holding).map { displayName(for: $0) } ?? holding.bankName
    }

    /// Bakiyelerim'deki toplam.
    var totalHoldingsBalance: Money {
        holdings.reduce(0) { $0 + $1.balance }
    }

    /// Henüz bakiyesi girilmemiş bankalar (her bankada en fazla bir kayıt).
    var banksWithoutHolding: [BankConditionDraft] {
        banks.filter { bank in !holdings.contains { $0.bankID == bank.id } }
    }

    /// Her kaydı bugüne işletir: son valör gününden bu yana valörü gelen net faiz,
    /// bağlı bankanın Düzenle'deki koşulları ve stopajla bakiyeye eklenir. Aynı
    /// gün tekrar çağrılırsa hiçbir şey eklemez. Uygulama açılışında, öne
    /// gelince ve açıkken gün dönünce çağrılır; kayıt oturumla birlikte (arka
    /// plana geçerken) yapılır.
    func accrueHoldings(today: Date = Date()) {
        let day = AccrualCalendar.day(for: today)
        for index in holdings.indices {
            accrueHolding(at: index, through: day)
        }
    }

    /// Tek kaydı `day`'e işletir (bkz. `accrueHoldings`).
    private func accrueHolding(at index: Int, through day: CalendarDay) {
        guard let bank = bank(for: holdings[index]) else {
            debugPrint("[AppState] \(holdings[index].bankName) bakiyesinin bankası Düzenle'de yok, faiz eklenmedi.")
            return
        }
        // Kopya üzerinde işlet: değişiklik yoksa gözlemcileri boşuna tetikleme.
        var holding = holdings[index]
        holding.bankName = displayName(for: bank)
        let added = HoldingLedger.accrue(&holding, condition: bank.makeCondition(),
                                         withholding: withholdingRule, through: day)
        if holding != holdings[index] {
            holdings[index] = holding
        }
        if !added.isEmpty {
            let total = added.reduce(Money(0)) { $0 + $1.change }
            debugPrint("[AppState] \(holding.bankName) bakiyesine \(added.count) valör gününün faizi eklendi: +\(total) ₺, bakiye \(holding.balance) ₺.")
        }
    }

    /// Yeni gerçek bakiye; bakiye bugün itibarıyla geçerlidir, faiz kaydın hafta
    /// sonu kuralıyla bugünün bloğundan (kaçırıldıysa bir sonrakinden) başlar.
    /// Bankada zaten kayıt varsa ya da banka yoksa eklenmez.
    @discardableResult
    func addHolding(bankID: UUID, balance: Money, weekendInterest: WeekendInterest = .threeNights,
                    missesTodaysInterest: Bool = false, today: Date = Date()) -> UUID? {
        guard let bank = banks.first(where: { $0.id == bankID }),
              !holdings.contains(where: { $0.bankID == bankID }) else {
            debugPrint("[AppState] Bakiye eklenmedi: banka yok ya da bankada zaten kayıt var.")
            return nil
        }
        let holding = HoldingLedger.open(bankID: bankID, bankName: displayName(for: bank),
                                         balance: balance, on: AccrualCalendar.day(for: today),
                                         weekendInterest: weekendInterest,
                                         missesTodaysInterest: missesTodaysInterest)
        holdings.append(holding)
        debugPrint("[AppState] Bakiye eklendi: \(holding.bankName), \(holding.balance) ₺, hafta sonu \(weekendInterest), bugünün faizi kaçırıldı: \(missesTodaysInterest), faiz \(AccrualCalendar.date(for: holding.asOf).formatted(date: .numeric, time: .omitted)) gecesinden başlıyor.")
        return holding.id
    }

    /// Kaydın bankasını, bakiyesini ve faiz seçimlerini değiştirir. Bakiye ya
    /// da "bugünün faizini kaçırdım" değiştiyse bakiye bugün itibarıyla bu
    /// seçimlerle yeniden girilir ("eklenen faiz" sıfırlanır); yalnız banka
    /// ve/veya hafta sonu kuralı değiştiyse bakiye korunur. Seçilen bankada
    /// başka kayıt varsa banka değişmez.
    func updateHolding(_ id: UUID, bankID: UUID, balance: Money, weekendInterest: WeekendInterest,
                       missesTodaysInterest: Bool, today: Date = Date()) {
        guard let index = holdings.firstIndex(where: { $0.id == id }) else { return }
        if bankID != holdings[index].bankID,
           let bank = banks.first(where: { $0.id == bankID }),
           !holdings.contains(where: { $0.bankID == bankID }) {
            holdings[index].bankID = bankID
            holdings[index].bankName = displayName(for: bank)
            debugPrint("[AppState] Bakiyenin bankası değişti: \(holdings[index].bankName).")
        }
        let day = AccrualCalendar.day(for: today)
        var holding = holdings[index]
        HoldingLedger.edit(&holding, balance: balance, weekendInterest: weekendInterest,
                           missesTodaysInterest: missesTodaysInterest, on: day)
        if holding != holdings[index] {
            holdings[index] = holding
            debugPrint("[AppState] \(holding.bankName) bakiyesi güncellendi: \(holding.balance) ₺, hafta sonu \(holding.weekendInterest), bugünün faizi kaçırıldı: \(missesTodaysInterest), faiz \(AccrualCalendar.date(for: holding.asOf).formatted(date: .numeric, time: .omitted)) gecesinden başlıyor.")
        }
        // Yalnız kural değiştiyse valörü gelmiş gece olabilir (Cumartesi 3
        // gecelikten 1 gecelike geçince Cuma gecesi): hemen eklensin.
        accrueHolding(at: index, through: day)
    }

    func deleteHolding(_ id: UUID) {
        holdings.removeAll { $0.id == id }
        debugPrint("[AppState] Bakiye kaydı silindi, kalan \(holdings.count) kayıt.")
    }

    func deleteHoldings(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where holdings.indices.contains(index) {
            holdings.remove(at: index)
        }
        debugPrint("[AppState] \(offsets.count) bakiye kaydı silindi, kalan \(holdings.count) kayıt.")
    }

    /// Kaydın bir sonraki valör günü ve o gün eklenecek gece sayısı; banka
    /// yoksa nil (faiz işlemez).
    func nextCredit(for holding: Holding, today: Date = Date()) -> HoldingLedger.Credit? {
        guard bank(for: holding) != nil else { return nil }
        return HoldingLedger.nextCredit(holding, after: AccrualCalendar.day(for: today))
    }

    /// Geçmiş ama valörü Pazartesi gelecek gecelerin net faizi (3 gecelikte
    /// hafta sonu); hafta içi, 1 gecelikte ya da banka yoksa 0.
    func pendingInterest(for holding: Holding, today: Date = Date()) -> Money {
        guard let bank = bank(for: holding) else { return 0 }
        return HoldingLedger.pendingInterest(holding, condition: bank.makeCondition(),
                                             withholding: withholdingRule,
                                             today: AccrualCalendar.day(for: today))
    }

    /// Mevcut bakiyenin bir gecelik net faizi; banka yoksa nil.
    func nightlyNet(for holding: Holding) -> Money? {
        guard let bank = bank(for: holding) else { return nil }
        return HoldingLedger.nightlyNet(holding, condition: bank.makeCondition(), withholding: withholdingRule)
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
