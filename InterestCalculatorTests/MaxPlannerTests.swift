//
//  MaxPlannerTests.swift
//  InterestCalculatorTests
//
//  Max planlayıcı. Kullanıcı senaryosu: A %38 brüt, %10 vadesiz; B %42 brüt,
//  kademeli (<25.000 şartsız, 25.000+ → 7.500, 50.000+ → 10.000, 100.000+ →
//  20.000 vadesiz); C %41 brüt, kademeli (<50.000 → 5.000, 50.000+ → 10.000
//  vadesiz); 152.000 ₺, 10 gün, Pazartesi başlangıç, stopaj %17,5, kademe payı
//  %10. Golden'lar motordan gelir ve B'nin 10 gecesi elle doğrulandı (valör:
//  Cuma+Cmt+Paz Pazartesi toplu). Optimumluk bağımsız bir kaba ızgara
//  aramasıyla da kontrol edilir.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Max Planlayıcı")
struct MaxPlannerTests {

    private let bankA = BankCondition(name: "A", rateRule: .flat(.percent(38)),
                                      idleRequirement: .percentage(.percent(10)))
    private let bankB = BankCondition(name: "B", rateRule: .flat(.percent(42)), idleRequirement: .tiered(
        TierTable(normalizing: [
            .init(upperBound: d("25000"), value: .fixedAmount(0)),
            .init(upperBound: d("50000"), value: .fixedAmount(d("7500"))),
            .init(upperBound: d("100000"), value: .fixedAmount(d("10000"))),
            .init(upperBound: nil, value: .fixedAmount(d("20000"))),
        ], fallback: .fixedAmount(0))
    ))
    private let bankC = BankCondition(name: "C", rateRule: .flat(.percent(41)), idleRequirement: .tiered(
        TierTable(normalizing: [
            .init(upperBound: d("50000"), value: .fixedAmount(d("5000"))),
            .init(upperBound: nil, value: .fixedAmount(d("10000"))),
        ], fallback: .fixedAmount(0))
    ))

    private var withholding: WithholdingRule { .single(.percent(d("17.5"))) }

    private func plan(_ banks: [BankCondition], amount: Decimal = d("152000"), nights: Int = 10,
                      start: Weekday = .monday,
                      buffer: Percentage = MaxPlanner.defaultBuffer) -> MaxPlan {
        MaxPlanner.plan(amount: amount, banks: banks, withholding: withholding, nights: nights,
                        startWeekday: start, buffer: buffer)
    }

    private func project(_ bank: BankCondition, _ deposit: Money, nights: Int = 10,
                         start: Weekday = .monday) -> InterestResult {
        CompoundingEngine.project(initialBalance: deposit, startWeekday: start, nights: nights,
                                  condition: bank, withholding: withholding)
    }

    private func oneNightNet(_ bank: BankCondition, at balance: Money) -> Money {
        InterestEngine.calculate(InterestInput(totalBalance: balance, nights: 1, condition: bank,
                                               withholding: withholding)).netInterest
    }

    /// Kullanıcı kuralı, planlayıcıdan bağımsız: kademeli bankada vade sonu
    /// bakiyesi yatırılan tutarın kademesinin üst sınırını geçmez ve sınıra en
    /// az 1 günlük net faiz × pay kalır.
    private func respectsTierRule(_ bank: BankCondition, deposit: Money, nights: Int = 10,
                                  start: Weekday = .monday,
                                  buffer: Percentage = MaxPlanner.defaultBuffer) -> Bool {
        guard case .tiered(let table) = bank.idleRequirement,
              let upper = table.resolve(for: deposit).tier.upperBound else { return true }
        let final = deposit + project(bank, deposit, nights: nights, start: start).netInterest
        return final < upper && upper - final >= buffer.applied(to: oneNightNet(bank, at: final))
    }

    private func allocation(_ plan: MaxPlan, _ name: String) -> MaxPlan.Allocation? {
        plan.allocations.first { $0.bankName == name }
    }

    // MARK: - Kullanıcı senaryosu

    @Test("Golden · 152.000 ₺, 10 gün: B 25 binin altında şartsız, C kalanla son kademede, A boş",
          .tags(.golden))
    func goldenUserScenario() throws {
        let result = plan([bankA, bankB, bankC])
        #expect(result.allocations.map(\.bankName) == ["B", "C"])
        #expect(result.unusedBanks.map(\.name) == ["A"])
        #expect(result.unallocated == 0)

        let b = try #require(allocation(result, "B"))
        #expect(b.tier?.index == 0)
        #expect(b.deposit == d("24761.64"))
        #expect(b.idleAmount == 0)
        #expect(b.netInterest == d("235.98"))
        #expect(b.finalBalance == d("24997.62"))
        #expect(b.oneDayNet == d("23.73"))
        #expect(b.headroom == d("2.38"))   // hedef pay 23,73 × %10 = 2,373

        let c = try #require(allocation(result, "C"))
        #expect(c.tier?.index == 1)
        #expect(c.deposit == d("127238.36"))
        #expect(c.idleAmount == d("10000"))
        #expect(c.netInterest == d("1090.68"))
        #expect(c.headroom == nil)   // son kademe sınırsız: pay kuralı yok

        #expect(result.totalNet == d("1326.66"))
        #expect(result.totalGross == d("1608.11"))
        #expect(result.totalDeductions == d("281.45"))
        #expect(result.bufferPercent == 10)
        #expect(result.withholdingPercent == d("17.5"))
    }

    @Test("Golden · tek bankada en iyisi hepsini C'ye koymak: 1.321,05 ₺; bölmek 5,61 ₺ fazla",
          .tags(.golden))
    func goldenBaseline() throws {
        let result = plan([bankA, bankB, bankC])
        let baseline = try #require(result.bestSingleBank)
        #expect(baseline.bankName == "C")
        #expect(baseline.deposit == d("152000"))
        #expect(baseline.netInterest == d("1321.05"))
        #expect(result.totalNet - baseline.netInterest == d("5.61"))
    }

    @Test("Kademe payı sıkı: B'ye 1 kuruş fazlası payı bozar", .tags(.boundary))
    func bufferIsTight() throws {
        let b = try #require(allocation(plan([bankA, bankB, bankC]), "B"))
        #expect(respectsTierRule(bankB, deposit: b.deposit))
        #expect(!respectsTierRule(bankB, deposit: b.deposit + d("0.01")))
        // Kalan pay 1 günlük faizden az (sınırı geçmeye bir günden az kaldı).
        let headroom = try #require(b.headroom)
        let oneDay = try #require(b.oneDayNet)
        #expect(headroom >= oneDay / 10)
        #expect(headroom < oneDay)
    }

    // MARK: - Optimumluk

    /// Bağımsız kontrol: her bankaya 1.000 ₺'lik adımlarla tutar dağıtan, tamamını
    /// yatıran ve kademe kuralını bozan noktaları eleyen kaba arama planı geçemez.
    @Test("Kaba ızgara araması planı geçemez", .tags(.invariant),
          arguments: [["A", "B", "C"], ["A", "B"], ["B", "C"], ["A", "C"]])
    func gridSearchCannotBeatPlan(names: [String]) {
        let all = ["A": bankA, "B": bankB, "C": bankC]
        let banks = names.compactMap { all[$0] }
        let step = d("1000")
        let steps = 152
        // Izgara noktalarındaki kazanç; kuralı bozan nokta nil.
        let tables: [[Money?]] = banks.map { bank in
            (0...steps).map { index in
                let deposit = step * Decimal(index)
                return respectsTierRule(bank, deposit: deposit) ? project(bank, deposit).netInterest : nil
            }
        }
        var best: Money = 0
        if banks.count == 2 {
            for i in 0...steps {
                guard let first = tables[0][i], let second = tables[1][steps - i] else { continue }
                best = max(best, first + second)
            }
        } else {
            for i in 0...steps {
                for j in 0...(steps - i) {
                    guard let first = tables[0][i], let second = tables[1][j],
                          let third = tables[2][steps - i - j] else { continue }
                    best = max(best, first + second + third)
                }
            }
        }
        #expect(best > 0)
        #expect(plan(banks).totalNet >= best)
    }

    @Test("A + B · B'yi 100 binin hemen altında tutup kalanı A'ya koymak hepsini B'ye koymaktan iyi")
    func tierTopBeatsAllInTopTier() throws {
        let result = plan([bankA, bankB])
        let b = try #require(allocation(result, "B"))
        let a = try #require(allocation(result, "A"))
        #expect(b.tier?.index == 2)
        #expect(respectsTierRule(bankB, deposit: b.deposit))
        #expect(!respectsTierRule(bankB, deposit: b.deposit + d("0.01")))
        #expect(a.deposit == d("152000") - b.deposit)
        let allInB = project(bankB, d("152000")).netInterest
        #expect(result.totalNet > allInB)
        #expect(result.bestSingleBank?.netInterest == allInB)
    }

    @Test("Yalnız C, 52.000 ₺ · 50 binin altında kalıp artanı dağıtmamak üst kademeden iyi")
    func leavesRemainderUnallocated() throws {
        let result = plan([bankC], amount: d("52000"))
        let c = try #require(allocation(result, "C"))
        #expect(c.tier?.index == 0)
        #expect(result.unallocated > 0)
        #expect(c.deposit + result.unallocated == d("52000"))
        #expect(!respectsTierRule(bankC, deposit: c.deposit + d("0.01")))
        // Tümünü yatırmak C'yi üst kademeye (10.000 vadesiz) taşır ve daha az kazandırır.
        #expect(result.totalNet > project(bankC, d("52000")).netInterest)
    }

    // MARK: - Vade ve pay oranı

    @Test("Vade uzadıkça kademe tepesindeki tutar azalır; her vadede pay kuralı sıkı")
    func longerHorizonDepositsLess() throws {
        let deposits = try [1, 10, 30, 90].map { nights -> Money in
            let b = try #require(allocation(plan([bankA, bankB, bankC], nights: nights), "B"))
            #expect(b.tier?.index == 0)
            #expect(respectsTierRule(bankB, deposit: b.deposit, nights: nights))
            #expect(!respectsTierRule(bankB, deposit: b.deposit + d("0.01"), nights: nights))
            return b.deposit
        }
        #expect(zip(deposits, deposits.dropFirst()).allSatisfy { $0 > $1 })
        #expect(deposits.first == d("24973.91"))   // 1 gün: 24.973,91 + 23,71 = 24.997,62
    }

    @Test("Pay oranı değişken: %50'de pay büyür, %0'da sınırın 1 kuruş altına kadar", .tags(.boundary))
    func bufferRatioIsAParameter() throws {
        let tenPercent = try #require(allocation(plan([bankA, bankB, bankC]), "B"))

        let half = Percentage.percent(50)
        let wide = try #require(allocation(plan([bankA, bankB, bankC], buffer: half), "B"))
        let wideHeadroom = try #require(wide.headroom)
        let wideOneDay = try #require(wide.oneDayNet)
        #expect(wide.deposit < tenPercent.deposit)
        #expect(wideHeadroom >= wideOneDay / 2)
        #expect(!respectsTierRule(bankB, deposit: wide.deposit + d("0.01"), buffer: half))
        #expect(plan([bankA, bankB, bankC], buffer: half).bufferPercent == 50)

        let none = try #require(allocation(plan([bankA, bankB, bankC], buffer: .zero), "B"))
        #expect(none.finalBalance == d("24999.99"))
        #expect(!respectsTierRule(bankB, deposit: none.deposit + d("0.01"), buffer: .zero))
    }

    // MARK: - Değişmezler

    @Test("Her tahsis motorla birebir, tutar tam dağılır, kural tutar, plan tek bankadan az değil",
          .tags(.invariant))
    func invariantsAcrossScenarios() {
        let scenarios: [(banks: [BankCondition], amount: Money)] = [
            ([bankA, bankB, bankC], d("152000")),
            ([bankA, bankB, bankC], d("60000")),
            ([bankA, bankB, bankC], d("300000")),
            ([bankB, bankC], d("20000")),
            ([bankC], d("52000")),
            ([bankA], d("1234.56")),
        ]
        for scenario in scenarios {
            for start in [Weekday.monday, .thursday, .friday, .sunday] {
                for nights in [1, 7, 10, 45] {
                    let result = plan(scenario.banks, amount: scenario.amount, nights: nights, start: start)
                    #expect(result.totalDeposited + result.unallocated == scenario.amount)
                    #expect(result.unallocated >= 0)
                    for item in result.allocations {
                        let bank = scenario.banks.first { $0.id == item.bankID }!
                        let direct = project(bank, item.deposit, nights: nights, start: start)
                        #expect(item.netInterest == direct.netInterest)
                        #expect(item.grossInterest == direct.totalGrossInterest)
                        #expect(item.deductions == direct.totalDeductions)
                        #expect(item.idleAmount == direct.idleAmount)
                        #expect(item.interestBearing == direct.interestBearingBalance)
                        #expect(item.deposit > 0)
                        #expect(respectsTierRule(bank, deposit: item.deposit, nights: nights, start: start))
                        if let upper = item.tier?.upperBound {
                            #expect(item.headroom == upper - item.finalBalance)
                        }
                    }
                    if let baseline = result.bestSingleBank {
                        #expect(result.totalNet >= baseline.netInterest)
                    }
                }
            }
        }
    }

    @Test("Deterministik: aynı girdi aynı plan")
    func deterministic() {
        #expect(plan([bankA, bankB, bankC]) == plan([bankA, bankB, bankC]))
    }

    // MARK: - Kademesiz bankalar, limit, en az bakiye

    @Test("Kademesiz · marjinal getirisi en yüksek banka tamamını alır")
    func flatBanksPickHighestMarginal() {
        let percent = BankCondition(name: "Yüzde", rateRule: .flat(.percent(45)),
                                    idleRequirement: .percentage(.percent(10)))   // marjinal %40,5
        let plain = BankCondition(name: "Şartsız", rateRule: .flat(.percent(40)))  // marjinal %40
        #expect(plan([plain, percent], amount: d("100000")).allocations.map(\.bankName) == ["Yüzde"])

        let fixed = BankCondition(name: "Sabit", rateRule: .flat(.percent(45)),
                                  idleRequirement: .fixedAmount(d("5000")))        // marjinal %45
        let result = plan([plain, percent, fixed], amount: d("100000"))
        #expect(result.allocations.map(\.bankName) == ["Sabit"])
        #expect(result.allocations.first?.deposit == d("100000"))
    }

    @Test("Faize giren limiti · limitli banka limite kadar, kalan sonraki bankaya")
    func capSplitsAtKink() {
        let capped = BankCondition(name: "Limitli", rateRule: .flat(.percent(50)),
                                   maxInterestBearingAmount: d("30000"))
        let plain = BankCondition(name: "Şartsız", rateRule: .flat(.percent(40)))
        let result = plan([capped, plain], amount: d("100000"))
        #expect(result.allocations.map(\.deposit) == [d("30000"), d("70000")])
    }

    @Test("En az bakiye şartı · tutar yetmiyorsa banka kullanılmaz, yetiyorsa şart karşılanır")
    func minimumBalance() {
        let premium = BankCondition(name: "Premium", rateRule: .flat(.percent(50)),
                                    minTotalBalance: d("50000"))
        let plain = BankCondition(name: "Şartsız", rateRule: .flat(.percent(40)))
        #expect(plan([premium, plain], amount: d("40000")).allocations.map(\.bankName) == ["Şartsız"])
        #expect(plan([premium, plain], amount: d("100000")).allocations.map(\.bankName) == ["Premium"])
    }

    // MARK: - Kenar durumlar

    @Test("Kenar · tutar 0, banka yok, oransız banka", .tags(.edgeCase))
    func edgeCases() {
        let zero = plan([bankA, bankB, bankC], amount: 0)
        #expect(zero.allocations.isEmpty)
        #expect(zero.unallocated == 0)
        #expect(zero.totalNet == 0)

        let noBanks = plan([], amount: d("1000"))
        #expect(noBanks.allocations.isEmpty)
        #expect(noBanks.unallocated == d("1000"))
        #expect(noBanks.bestSingleBank == nil)

        let rateless = plan([BankCondition(name: "Boş", rateRule: .flat(.zero))], amount: d("1000"))
        #expect(rateless.allocations.isEmpty)
        #expect(rateless.unusedBanks.map(\.name) == ["Boş"])
        #expect(rateless.unallocated == d("1000"))
    }

    @Test("Kenar · gün 1...365'e, tutar kuruşa kırpılır", .tags(.edgeCase))
    func clamping() {
        #expect(plan([bankA], nights: 0).nights == 1)
        #expect(plan([bankA], nights: 1000).nights == 365)
        #expect(plan([bankA], amount: d("100.009")).amount == d("100"))
    }
}
