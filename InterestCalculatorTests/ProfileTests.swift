//
//  ProfileTests.swift
//  InterestCalculatorTests
//
//  Profil sekmesi: takvim günü ↔ tarih eşlemesi, AppState üzerinden
//  Bakiyelerim (ekleme, açılışta işletme, banka silinince donma, güncelleme),
//  profil alanlarından önceki oturumların çözülmesi ve baş harfler.
//  AppState/AccrualCalendar MainActor olduğu için suite @MainActor. save() /
//  SessionStore ÇAĞRILMAZ: testler uygulama sürecinde çalışır ve simülatördeki
//  gerçek oturumun üzerine yazar.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Profil ve Bakiyelerim")
@MainActor
struct ProfileTests {

    /// Öğlen 12:00 — gün başı sınır belirsizliğini eler.
    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        return AccrualCalendar.calendar.date(from: components)!
    }

    /// İki banka: %45 brüt şartsız ve %40 net; stopaj %17,5.
    private func makeState() -> AppState {
        let state = AppState(loadPersisted: false)
        state.withholdingText = "17.5"
        state.banks = [BankConditionDraft(name: "Şartsız", annualRateText: "45"), .sampleNet]
        return state
    }

    @Test("Takvim günü ↔ tarih: 2001-01-01 = 0, 2026-10-05 = 9408 (Pazartesi)")
    func calendarDayMapping() {
        #expect(AccrualCalendar.day(for: date(2001, 1, 1)) == CalendarDay(index: 0))
        #expect(AccrualCalendar.day(for: date(2026, 10, 5)) == CalendarDay(index: 9408))
        #expect(AccrualCalendar.day(for: date(2026, 10, 5, hour: 0)) == CalendarDay(index: 9408))
        #expect(AccrualCalendar.day(for: date(2026, 10, 5, hour: 23)) == CalendarDay(index: 9408))

        // İki yılı aşkın ardışık gün: hafta günü Foundation ile aynı, gidiş-dönüş gün başına döner.
        var mismatches: [Date] = []
        var cursor = date(2025, 1, 1)
        for _ in 0..<800 {
            let day = AccrualCalendar.day(for: cursor)
            if day.weekday != AccrualCalendar.weekday(for: cursor)
                || AccrualCalendar.date(for: day) != AccrualCalendar.startOfDay(cursor) {
                mismatches.append(cursor)
            }
            cursor = AccrualCalendar.calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("Bakiye eklenir; açılışta valörü gelen faiz işler, aynı gün tekrar işlemez", .tags(.golden))
    func addAndAccrue() throws {
        let state = makeState()
        let id = try #require(state.addHolding(bankID: state.banks[0].id, balance: d("100000"),
                                               today: date(2026, 10, 5)))
        state.accrueHoldings(today: date(2026, 10, 9))   // Cuma
        let holding = try #require(state.holdings.first { $0.id == id })
        #expect(holding.balance == d("100407.46"))
        #expect(state.totalHoldingsBalance == d("100407.46"))
        #expect(state.nightlyNet(for: holding) == d("102.13"))

        state.accrueHoldings(today: date(2026, 10, 9, hour: 23))
        #expect(state.holdings[0] == holding)

        // Hafta sonu: bakiye değişmez, biriken gösterilir; Pazartesi eklenir.
        state.accrueHoldings(today: date(2026, 10, 11))
        #expect(state.holdings[0] == holding)
        #expect(state.pendingInterest(for: state.holdings[0], today: date(2026, 10, 11)) == d("204.26"))
        state.accrueHoldings(today: date(2026, 10, 12))
        #expect(state.holdings[0].balance == d("100713.85"))
    }

    @Test("Her bankada bir kayıt; bilinmeyen bankaya kayıt eklenmez")
    func oneHoldingPerBank() {
        let state = makeState()
        #expect(state.addHolding(bankID: state.banks[0].id, balance: 1000) != nil)
        #expect(state.addHolding(bankID: state.banks[0].id, balance: 2000) == nil)
        #expect(state.addHolding(bankID: UUID(), balance: 2000) == nil)
        #expect(state.holdings.count == 1)
        #expect(state.banksWithoutHolding.map(\.id) == [state.banks[1].id])
    }

    @Test("Banka Düzenle'den silinirse kayıt kalır ama faiz işlemez; son bilinen adla görünür")
    func missingBankFreezes() throws {
        let state = makeState()
        try #require(state.addHolding(bankID: state.banks[0].id, balance: d("100000"),
                                      today: date(2026, 10, 5)) != nil)
        state.deleteBanks(at: [0])
        state.accrueHoldings(today: date(2026, 10, 9))

        let holding = state.holdings[0]
        #expect(holding.balance == d("100000"))
        #expect(holding.asOf == CalendarDay(index: 9408))
        #expect(state.bank(for: holding) == nil)
        #expect(state.displayName(for: holding) == "Şartsız")
        #expect(state.nightlyNet(for: holding) == nil)
        #expect(state.pendingInterest(for: holding, today: date(2026, 10, 10)) == 0)
    }

    @Test("Güncelleme: yalnız banka değişirse bakiye korunur; tutar değişirse o gün itibarıyla sıfırlanır")
    func updateHolding() throws {
        let state = makeState()
        let id = try #require(state.addHolding(bankID: state.banks[0].id, balance: d("100000"),
                                               today: date(2026, 10, 5)))
        state.accrueHoldings(today: date(2026, 10, 7))
        let accrued = state.holdings[0]
        #expect(accrued.balance == d("100203.52"))

        state.updateHolding(id, bankID: state.banks[1].id, balance: accrued.balance, today: date(2026, 10, 7))
        #expect(state.holdings[0].bankID == state.banks[1].id)
        #expect(state.holdings[0].bankName == "Net Banka")
        #expect(state.holdings[0].balance == accrued.balance)
        #expect(state.holdings[0].asOf == accrued.asOf)
        #expect(state.holdings[0].entries == accrued.entries)

        state.updateHolding(id, bankID: state.banks[1].id, balance: d("50000"), today: date(2026, 10, 7))
        #expect(state.holdings[0].balance == d("50000"))
        #expect(state.holdings[0].accruedInterest == 0)
        #expect(state.holdings[0].enteredOn == AccrualCalendar.day(for: date(2026, 10, 7)))
        #expect(state.holdings[0].entries.count == accrued.entries.count + 1)
    }

    @Test("Silme: kayıt ve onunla birlikte toplam gider; bankası yeniden seçilebilir")
    func deleteHolding() throws {
        let state = makeState()
        let id = try #require(state.addHolding(bankID: state.banks[0].id, balance: 1000))
        try #require(state.addHolding(bankID: state.banks[1].id, balance: 2000) != nil)
        state.deleteHolding(id)
        #expect(state.holdings.map(\.balance) == [2000])
        #expect(state.totalHoldingsBalance == 2000)
        #expect(state.banksWithoutHolding.map(\.id) == [state.banks[0].id])
        state.deleteHoldings(at: [0])
        #expect(state.holdings.isEmpty)
    }

    @Test("Profil alanlarından önce kaydedilmiş oturum çözülür")
    func legacySnapshotDecodes() throws {
        let banks = [BankConditionDraft.sample]
        let legacy = SessionSnapshot(balanceText: "100.000", withholdingText: "17.5", nights: 3,
                                     selectedBankID: nil, selectedTab: .max,
                                     banks: banks, maxHistory: [])
        let json = try #require(String(data: JSONEncoder().encode(legacy), encoding: .utf8))
        #expect(!json.contains("holdings") && !json.contains("profile") && !json.contains("appearance"))
        #expect(!json.contains("language"))

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
        #expect(decoded.holdings == nil)
        #expect(decoded.profile == nil)
        #expect(decoded.appearance == nil)
        #expect(decoded.language == nil)
        #expect(decoded.banks == banks)
        #expect(decoded.selectedTab == .max)
    }

    @Test("Oturum profili, görünümü, dili, bakiyeleri ve Profil sekmesini taşır")
    func snapshotCarriesProfile() throws {
        var holding = HoldingLedger.open(bankID: UUID(), bankName: "B", balance: d("60000.37"),
                                         on: CalendarDay(index: 9408))
        HoldingLedger.accrue(&holding, condition: BankCondition(name: "B", rateRule: .flat(.percent(45))),
                             withholding: .single(.percent(d("17.5"))), through: CalendarDay(index: 9415))
        let snapshot = SessionSnapshot(balanceText: "", withholdingText: "17.5", nights: 1,
                                       selectedBankID: nil, selectedTab: .profile, banks: [],
                                       maxHistory: nil,
                                       profile: UserProfile(firstName: "Ayşe", lastName: "Yılmaz"),
                                       appearance: .dark, language: .english, holdings: [holding])
        let data = try JSONEncoder().encode(snapshot)
        #expect(String(data: data, encoding: .utf8)?.contains(#""language":"en""#) == true)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.holdings == [holding])
        #expect(decoded.profile == snapshot.profile)
        #expect(decoded.appearance == .dark)
        #expect(decoded.language == .english)
        #expect(decoded.selectedTab == .profile)
    }

    @Test("Ad soyad ve baş harfler: Türkçe büyük harf, boşluklar atılır, ad yoksa nil")
    func profileNames() {
        #expect(UserProfile(firstName: "ilker", lastName: "ışık").initials == "İI")
        #expect(UserProfile(firstName: " Ayşe ", lastName: "").initials == "A")
        #expect(UserProfile(firstName: " Ayşe ", lastName: " Yılmaz").fullName == "Ayşe Yılmaz")
        #expect(UserProfile().initials == nil)
        #expect(UserProfile(firstName: "  ", lastName: "").fullName == nil)
    }
}
