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
//  aramasıyla da kontrol edilir. EFT kuralı: ücret para ayrılan bankanın
//  kazancından bir kez düşülür; bankanın kendi karı 20 ₺'yi aşmıyorsa o bankaya
//  para ayrılmaz.
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
                      buffer: Percentage = MaxPlanner.defaultBuffer,
                      eftFees: [UUID: Money] = [:],
                      minimumProfit: Money = MaxPlanner.defaultMinimumProfit) -> MaxPlan {
        MaxPlanner.plan(amount: amount, banks: banks, eftFees: eftFees, withholding: withholding,
                        nights: nights, startWeekday: start, buffer: buffer,
                        minimumProfit: minimumProfit)
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

    /// Kullanıcı kuralı, planlayıcıdan bağımsız: para ayrılan bankanın karı
    /// (N günlük net kazanç − EFT) 20 ₺'yi AŞAR.
    private func earnsEnough(_ bank: BankCondition, deposit: Money, eftFee: Money = 0,
                             nights: Int = 10, start: Weekday = .monday) -> Bool {
        project(bank, deposit, nights: nights, start: start).netInterest - eftFee
            > MaxPlanner.defaultMinimumProfit
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
        // EFT'siz: kar = net kazanç; eşik plana kaydedilir.
        #expect(result.totalEftFees == 0)
        #expect(result.totalProfit == d("1326.66"))
        #expect(result.minimumProfit == 20)
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
    /// yatıran, kademe kuralını ve 20 ₺ kuralını bozan noktaları eleyen kaba arama
    /// planı geçemez. EFT'li çeşitte B'nin ücreti (6 ₺) bölmenin getirisini aşar.
    @Test("Kaba ızgara araması planı geçemez", .tags(.invariant),
          arguments: [["A", "B", "C"], ["A", "B"], ["B", "C"], ["A", "C"]], [false, true])
    func gridSearchCannotBeatPlan(names: [String], withFees: Bool) {
        let all = ["A": bankA, "B": bankB, "C": bankC]
        let banks = names.compactMap { all[$0] }
        let fees: [UUID: Money] = withFees
            ? [bankA.id: d("4"), bankB.id: d("6"), bankC.id: d("2.5")]
            : [:]
        let step = d("1000")
        let steps = 152
        // Izgara noktalarındaki kar (net − EFT); 0 = banka kullanılmaz; kuralı bozan nokta nil.
        let tables: [[Money?]] = banks.map { bank in
            let fee = fees[bank.id] ?? 0
            return (0...steps).map { index in
                let deposit = step * Decimal(index)
                guard deposit > 0 else { return 0 }
                guard respectsTierRule(bank, deposit: deposit),
                      earnsEnough(bank, deposit: deposit, eftFee: fee) else { return nil }
                return project(bank, deposit).netInterest - fee
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
        #expect(plan(banks, eftFees: fees).totalProfit >= best)
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

    @Test("Her tahsis motorla birebir, tutar tam dağılır, kurallar tutar, plan tek bankadan az değil",
          .tags(.invariant), arguments: [false, true])
    func invariantsAcrossScenarios(withFees: Bool) {
        let fees: [UUID: Money] = withFees
            ? [bankA.id: d("3"), bankB.id: d("8"), bankC.id: d("1.5")]
            : [:]
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
                    let result = plan(scenario.banks, amount: scenario.amount, nights: nights,
                                      start: start, eftFees: fees)
                    #expect(result.totalDeposited + result.unallocated == scenario.amount)
                    #expect(result.unallocated >= 0)
                    #expect(result.totalProfit == result.totalNet - result.totalEftFees)
                    for item in result.allocations {
                        let bank = scenario.banks.first { $0.id == item.bankID }!
                        let direct = project(bank, item.deposit, nights: nights, start: start)
                        #expect(item.netInterest == direct.netInterest)
                        #expect(item.grossInterest == direct.totalGrossInterest)
                        #expect(item.deductions == direct.totalDeductions)
                        #expect(item.idleAmount == direct.idleAmount)
                        #expect(item.interestBearing == direct.interestBearingBalance)
                        #expect(item.deposit > 0)
                        #expect(item.eftFee == fees[bank.id] ?? 0)
                        #expect(item.profit == direct.netInterest - (fees[bank.id] ?? 0))
                        #expect(item.profit > MaxPlanner.defaultMinimumProfit)
                        #expect(respectsTierRule(bank, deposit: item.deposit, nights: nights, start: start))
                        if let upper = item.tier?.upperBound {
                            #expect(item.headroom == upper - item.finalBalance)
                        }
                    }
                    if let baseline = result.bestSingleBank {
                        #expect(result.totalProfit >= baseline.profit)
                        #expect(baseline.profit > MaxPlanner.defaultMinimumProfit)
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

    // MARK: - EFT ve 20 ₺ kuralı

    @Test("EFT · kazançtan bir kez düşülür; bölmeyi bozmuyorsa tutarlar değişmez", .tags(.golden))
    func eftFeeIsDeductedOnce() throws {
        // Bölmek C'ye göre 5,61 ₺ fazla net kazandırır; B'nin 5 ₺'si bunu yemez.
        let result = plan([bankA, bankB, bankC], eftFees: [bankB.id: d("5"), bankC.id: d("2")])
        #expect(result.allocations.map(\.bankName) == ["B", "C"])
        let b = try #require(allocation(result, "B"))
        let c = try #require(allocation(result, "C"))
        #expect(b.deposit == d("24761.64"))
        #expect(c.deposit == d("127238.36"))
        #expect(b.eftFee == 5)
        #expect(b.profit == d("230.98"))   // 235,98 − 5
        #expect(c.profit == d("1088.68"))  // 1.090,68 − 2
        #expect(result.totalNet == d("1326.66"))
        #expect(result.totalEftFees == 7)
        #expect(result.totalProfit == d("1319.66"))

        // Tek bankada en iyisi de kendi EFT'sini öder: 1.321,05 − 2.
        let baseline = try #require(result.bestSingleBank)
        #expect(baseline.bankName == "C")
        #expect(baseline.eftFee == 2)
        #expect(baseline.profit == d("1319.05"))
        #expect(result.totalProfit - baseline.profit == d("0.61"))
    }

    @Test("EFT · B'nin ücreti bölmenin getirisini aşınca hepsi C'ye gider")
    func eftFeeCanCancelSplit() throws {
        let result = plan([bankA, bankB, bankC], eftFees: [bankB.id: d("6")])
        #expect(result.allocations.map(\.bankName) == ["C"])
        #expect(result.allocations.first?.deposit == d("152000"))
        #expect(result.totalProfit == d("1321.05"))   // C'nin EFT'si yok
        // B kendi başına 20 ₺'den çok kazandırırdı; dışarıda kalma nedeni toplam kar.
        #expect(earnsEnough(bankB, deposit: d("24761.64"), eftFee: d("6")))
        #expect(result.unusedBanks.map(\.name) == ["A", "B"])
        #expect(result.unusedBanks.first { $0.name == "B" }?.eftFee == 6)
    }

    @Test("20 ₺ kuralı · karı tam 20 ₺ olan banka kullanılmaz, 20,01 ₺ olan kullanılır",
          .tags(.boundary))
    func minimumProfitIsExclusive() throws {
        let flat = BankCondition(name: "Şartsız", rateRule: .flat(.percent(45)))
        let amount = d("50000")
        let net = project(flat, amount).netInterest

        let atThreshold = plan([flat], amount: amount, eftFees: [flat.id: net - 20])
        #expect(atThreshold.allocations.isEmpty)
        #expect(atThreshold.unallocated == amount)
        #expect(atThreshold.unusedBanks.first?.eftFee == net - 20)
        #expect(atThreshold.bestSingleBank == nil)

        let above = plan([flat], amount: amount, eftFees: [flat.id: net - d("20.01")])
        let only = try #require(above.allocations.first)
        #expect(only.deposit == amount)
        #expect(only.profit == d("20.01"))
    }

    @Test("20 ₺ kuralı · küçük tutarda EFT'siz banka da kullanılmaz; para dağıtılmaz")
    func smallAmountStaysUnallocated() {
        let flat = BankCondition(name: "Şartsız", rateRule: .flat(.percent(45)))
        #expect(project(flat, d("1000")).netInterest < 20)
        let result = plan([flat], amount: d("1000"))
        #expect(result.allocations.isEmpty)
        #expect(result.unallocated == d("1000"))
        #expect(result.unusedBanks.map(\.name) == ["Şartsız"])
        #expect(result.bestSingleBank == nil)
    }

    @Test("20 ₺ kuralı · toplamı artırsa da kendi karı 20 ₺'yi geçmeyen banka kullanılmaz")
    func ownProfitDecidesNotContribution() throws {
        // Limitli banka yalnız 1.000 ₺'ye %60 verir: 10 günde ~13,5 ₺ (Düz'den iyi, ama < 20).
        let capped = BankCondition(name: "Limitli", rateRule: .flat(.percent(60)),
                                   maxInterestBearingAmount: d("1000"))
        let plain = BankCondition(name: "Düz", rateRule: .flat(.percent(40)))
        let amount = d("100000")

        let noRule = plan([capped, plain], amount: amount, minimumProfit: 0)
        #expect(noRule.allocations.map(\.bankName) == ["Limitli", "Düz"])
        let cappedPart = try #require(allocation(noRule, "Limitli"))
        #expect(cappedPart.profit < 20)

        let withRule = plan([capped, plain], amount: amount)
        #expect(withRule.allocations.map(\.bankName) == ["Düz"])
        #expect(withRule.allocations.first?.deposit == amount)
        #expect(withRule.totalProfit < noRule.totalProfit)   // kural bilinçli olarak kazançtan vazgeçer
    }

    @Test("20 ₺ kuralı · eşik değişken ve plana kaydedilir; negatif eşik 0 sayılır")
    func minimumProfitIsAParameter() {
        #expect(plan([bankA], minimumProfit: 50).minimumProfit == 50)
        #expect(plan([bankA], minimumProfit: -5).minimumProfit == 0)
        // 1.000 ₺ / 10 gün A: ~7,8 ₺ — 0 eşikte kullanılır, 20 ₺ eşikte kullanılmaz.
        #expect(plan([bankA], amount: d("1000"), minimumProfit: 0).allocations.count == 1)
        #expect(plan([bankA], amount: d("1000")).allocations.isEmpty)
    }

    @Test("Kenar · EFT: negatif ücret 0, kuruşa yuvarlanır, listede olmayan banka 0 öder",
          .tags(.edgeCase))
    func eftFeeEdgeCases() {
        let negative = plan([bankA], eftFees: [bankA.id: -5])
        #expect(negative.allocations.first?.eftFee == 0)

        let fractional = plan([bankA], eftFees: [bankA.id: d("5.555")])
        #expect(fractional.allocations.first?.eftFee == d("5.56"))

        let unknown = plan([bankA], eftFees: [UUID(): 10])
        #expect(unknown.allocations.first?.eftFee == 0)
        #expect(unknown.totalProfit == unknown.totalNet)
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
