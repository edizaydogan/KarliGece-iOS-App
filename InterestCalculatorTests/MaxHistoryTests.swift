//
//  MaxHistoryTests.swift
//  InterestCalculatorTests
//
//  Max geçmişi: kaydın JSON'da kuruş kaybetmemesi, geçmiş ve EFT alanlarından
//  önceki oturumların çözülmesi, sıra ve sınır, planlayıcı girdisinin gösterim
//  adları ve EFT ücretleri.
//  AppState/SessionSnapshot MainActor olduğu için suite @MainActor. save() /
//  SessionStore ÇAĞRILMAZ: testler uygulama sürecinde çalışır ve simülatördeki
//  gerçek oturumun üzerine yazar.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Max Geçmişi")
@MainActor
struct MaxHistoryTests {

    private func record(amount: Money = d("152000"), createdAt: Date = Date()) -> MaxPlanRecord {
        let tiered = BankCondition(name: "B", rateRule: .flat(.percent(42)), idleRequirement: .tiered(
            TierTable(normalizing: [
                .init(upperBound: d("25000"), value: .fixedAmount(0)),
                .init(upperBound: nil, value: .fixedAmount(d("20000"))),
            ], fallback: .fixedAmount(0))
        ))
        let percent = BankCondition(name: "A", rateRule: .flat(.percent(d("38.25"))),
                                    idleRequirement: .percentage(.percent(10)))
        let plan = MaxPlanner.plan(amount: amount, banks: [percent, tiered],
                                   withholding: .single(.percent(d("17.5"))),
                                   nights: 10, startWeekday: .monday)
        return MaxPlanRecord(id: UUID(), createdAt: createdAt,
                             startDate: AccrualCalendar.today(), plan: plan)
    }

    @Test("Kayıt JSON'da kuruş kaybetmeden geri gelir")
    func recordRoundTrip() throws {
        let original = record(amount: d("60000.37"))
        #expect(original.plan.allocations.contains { $0.headroom != nil })   // kademe alanları dolu
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MaxPlanRecord.self, from: data)
        #expect(decoded == original)
        #expect(decoded.plan.totalNet == original.plan.totalNet)
    }

    /// Kodlanmış JSON'dan bir anahtarı metin üzerinde siler (eski biçimi taklit
    /// eder). JSONSerialization'dan geçirilmez: sayılar Double'a dönüşüp kuruş kaybetmesin.
    private func removingKey(_ key: String, from json: String) -> String {
        let pair = "\"\(key)\":(\"[^\"]*\"|[-0-9.eE+]+)"
        return json
            .replacingOccurrences(of: "," + pair, with: "", options: .regularExpression)
            .replacingOccurrences(of: pair + ",", with: "", options: .regularExpression)
    }

    @Test("EFT alanlarından önce kaydedilmiş plan çözülür: EFT 0 sayılır, kar eşiği yok")
    func legacyRecordWithoutEftDecodes() throws {
        let original = record(amount: d("60000.37"))
        var json = try #require(String(data: JSONEncoder().encode(original), encoding: .utf8))
        #expect(json.contains("\"eftFee\"") && json.contains("\"minimumProfit\""))
        json = removingKey("minimumProfit", from: removingKey("eftFee", from: json))
        #expect(!json.contains("eftFee") && !json.contains("minimumProfit"))

        let decoded = try JSONDecoder().decode(MaxPlanRecord.self, from: Data(json.utf8))
        #expect(decoded.plan.minimumProfit == nil)
        #expect(decoded.plan.bestSingleBank?.eftFee == nil)
        #expect(decoded.plan.allocations.map(\.deposit) == original.plan.allocations.map(\.deposit))
        #expect(decoded.plan.allocations.allSatisfy { $0.eftFee == nil && $0.profit == $0.netInterest })
        #expect(decoded.plan.totalProfit == original.plan.totalNet)
    }

    @Test("EFT alanından önce kaydedilmiş banka taslağı çözülür: EFT boş (0 ₺)")
    func legacyDraftWithoutEftDecodes() throws {
        var draft = BankConditionDraft.sample
        draft.eftFeeText = "7,50"
        var json = try #require(String(data: JSONEncoder().encode(draft), encoding: .utf8))
        #expect(json.contains("eftFeeText"))
        json = removingKey("eftFeeText", from: json)
        #expect(!json.contains("eftFeeText"))

        let decoded = try JSONDecoder().decode(BankConditionDraft.self, from: Data(json.utf8))
        var expected = draft
        expected.eftFeeText = ""
        #expect(decoded == expected)
        #expect(decoded.eftFee == 0)
    }

    @Test("EFT metni kaydedilir ve ayrıştırılır; motor koşuluna girmez")
    func eftFeeDraft() throws {
        var draft = BankConditionDraft.sample
        draft.eftFeeText = "7,50"
        let decoded = try JSONDecoder().decode(BankConditionDraft.self, from: JSONEncoder().encode(draft))
        #expect(decoded == draft)
        #expect(decoded.eftFee == d("7.5"))

        var withoutFee = draft
        withoutFee.eftFeeText = ""
        #expect(draft.makeCondition() == withoutFee.makeCondition())

        for text in ["", "abc", "-5"] {
            #expect(BankConditionDraft(eftFeeText: text).eftFee == 0)
        }
    }

    @Test("Geçmiş alanından önce kaydedilmiş oturum çözülür")
    func legacySnapshotDecodes() throws {
        let banks = [BankConditionDraft.sample]
        let legacy = SessionSnapshot(balanceText: "100.000", withholdingText: "17.5", nights: 3,
                                     selectedBankID: nil, selectedTab: .compare,
                                     banks: banks, maxHistory: nil)
        let data = try JSONEncoder().encode(legacy)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("maxHistory"))   // eski biçimle aynı: anahtar yok

        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.maxHistory == nil)
        #expect(decoded.banks == banks)
        #expect(decoded.selectedTab == .compare)
    }

    @Test("Oturum geçmişi ve Max sekmesini taşır")
    func snapshotCarriesHistory() throws {
        let item = record()
        let snapshot = SessionSnapshot(balanceText: "", withholdingText: "17.5", nights: 1,
                                       selectedBankID: nil, selectedTab: .max,
                                       banks: [], maxHistory: [item])
        let decoded = try JSONDecoder().decode(SessionSnapshot.self,
                                               from: JSONEncoder().encode(snapshot))
        #expect(decoded.maxHistory == [item])
        #expect(decoded.selectedTab == .max)
    }

    @Test("Geçmiş en yeni başta; sınırı aşan en eski kayıtlar düşer")
    func orderAndLimit() {
        let state = AppState(loadPersisted: false)
        let first = record()
        let second = record()
        state.recordMaxPlan(first)
        state.recordMaxPlan(second)
        #expect(state.maxHistory.map(\.id) == [second.id, first.id])

        for _ in 0..<AppState.maxHistoryLimit {
            state.recordMaxPlan(record(amount: d("1000")))
        }
        #expect(state.maxHistory.count == AppState.maxHistoryLimit)
        #expect(!state.maxHistory.contains { $0.id == first.id })   // en eskiler düştü
    }

    @Test("Temizle tüm geçmişi siler, oturumun geri kalanına dokunmaz")
    func clearRemovesAllRecords() {
        let state = AppState(loadPersisted: false)
        state.balanceText = "152.000"
        state.banks = [.sample]
        let banks = state.banks
        for _ in 0..<3 {
            state.recordMaxPlan(record())
        }
        state.clearMaxHistory()
        #expect(state.maxHistory.isEmpty)
        #expect(state.balanceText == "152.000")
        #expect(state.banks == banks)

        // Temizlikten sonra yeni hesap yine geçmişe eklenir.
        state.recordMaxPlan(record())
        #expect(state.maxHistory.count == 1)
    }

    @Test("Planlayıcı girdisi gösterim adlarını ve EFT ücretlerini taşır; motor koşulu aynı")
    func planningConditions() {
        let state = AppState(loadPersisted: false)
        state.banks = [.sample, .blankDefault]
        state.banks[0].eftFeeText = "7,50"
        let conditions = state.planningConditions
        #expect(conditions.map(\.name) == ["Örnek Banka", "Adsız banka 2"])
        var expected = state.banks[1].makeCondition()
        expected.name = "Adsız banka 2"
        #expect(conditions[1] == expected)
        #expect(state.planningEftFees == [state.banks[0].id: d("7.5"), state.banks[1].id: 0])
    }
}
