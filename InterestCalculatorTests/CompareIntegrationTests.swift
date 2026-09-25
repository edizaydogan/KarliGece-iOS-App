//
//  CompareIntegrationTests.swift
//  InterestCalculatorTests
//
//  Karşılaştır ↔ Özet sınırı. AppState MainActor olduğu için bu suite @MainActor
//  (saf motor testlerinin nonisolated kuralı burada geçerli değil). save() /
//  SessionStore ÇAĞRILMAZ: testler uygulama sürecinde çalışır ve simülatördeki
//  gerçek oturumun üzerine yazar.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Karşılaştır ↔ Özet")
@MainActor
struct CompareIntegrationTests {

    /// 2026-01-05 Pazartesi 00:00 — hafta günü sabit, testler deterministik.
    private var monday: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 5; components.hour = 12
        return AccrualCalendar.startOfDay(AccrualCalendar.calendar.date(from: components)!)
    }

    private func makeState() -> AppState {
        let state = AppState(loadPersisted: false)
        state.balanceText = "100.000"
        state.withholdingText = "17.5"
        state.banks = [.sample, .sampleFlat, .sampleNet]
        state.selectedBankID = state.banks[0].id
        state.startDate = monday
        state.nights = 1
        return state
    }

    @Test("Tohum bir kez alınır; Karşılaştır seçimi Özet'i değiştirmez")
    func seedOnceAndIndependent() {
        let state = makeState()
        let ids = state.banks.map(\.id)
        var selection = CompareSelection(seed: state.selectedBank?.id)
        #expect(selection.resolvedIDs(in: ids).first == ids[0])

        // Özet'te (Düzenle'de) başka banka seçilir → Karşılaştır'ın 1. sütunu değişmez.
        state.selectedBankID = ids[2]
        #expect(selection.resolvedIDs(in: ids).first == ids[0])

        // Karşılaştır'da 1. sütun değişir → Özet'in seçimi değişmez.
        selection.select(ids[1], forColumn: 0, in: ids)
        #expect(selection.resolvedIDs(in: ids).first == ids[1])
        #expect(state.selectedBankID == ids[2])
    }

    @Test("Özet'in 7 gecesi, Karşılaştır'ın 7 günlük hücresiyle birebir aynı")
    func summaryMatchesCompare() throws {
        let state = makeState()
        state.nights = 7   // Pazartesi + 7 = Pazartesi → snap yok
        let summary = try #require(state.result)
        let balance = try #require(state.parsedBalance)
        let bank = try #require(state.selectedBank)
        let sevenDays = try #require(CompareCalculator.horizons.firstIndex(of: 7))

        let table = CompareCalculator.projections(
            balance: balance, conditions: [bank.makeCondition()],
            withholding: state.withholdingRule, startWeekday: .monday
        )
        #expect(table[0][sevenDays] == summary)
    }

    @Test("parsedBalance / withholdingRule çıkarımı Özet sonucunu değiştirmez")
    func resultUnchanged() throws {
        let state = makeState()
        #expect(state.parsedBalance == d("100000"))
        #expect(state.withholdingRule == .single(.percent(d("17.5"))))

        let result = try #require(state.result)
        #expect(result == CompoundingEngine.project(
            initialBalance: d("100000"), startWeekday: .monday, nights: 1,
            condition: state.banks[0].makeCondition(),
            withholding: .single(.percent(d("17.5")))
        ))
        #expect(result.netInterest == d("91.54"))   // Golden #1

        state.balanceText = ""
        #expect(state.result == nil)
        state.withholdingText = "abc"
        #expect(state.withholdingRule == WithholdingRule.none)
    }

    @Test("Adsız bankalar listedeki sırasıyla ayırt edilir")
    func displayNames() {
        let state = makeState()
        state.banks.append(.blankDefault)
        state.banks.append(BankConditionDraft(name: "   "))
        #expect(state.displayName(for: state.banks[0]) == "Örnek Banka")
        #expect(state.displayName(for: state.banks[3]) == "Adsız banka 4")
        #expect(state.displayName(for: state.banks[4]) == "Adsız banka 5")
    }
}
