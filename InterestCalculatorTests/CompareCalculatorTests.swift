//
//  CompareCalculatorTests.swift
//  InterestCalculatorTests
//
//  Karşılaştır hesabı: sabit vadeler, motorla birebir tutarlılık, monotonluk ve
//  sıralama. 1 günlük golden'lar mevcut CompoundingEngineTests'le aynı senaryo
//  (100.000 ₺, stopaj %17,5, ACT/365); uzun vadeler için elle golden YAZILMAZ.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Karşılaştır Hesabı")
struct CompareCalculatorTests {

    /// A: %45 brüt, %10 vadesiz (Golden #1).
    private let bankA = BankCondition(name: "A", rateRule: .flat(.percent(45)),
                                      idleRequirement: .percentage(.percent(10)))
    /// B: %45 brüt, şartsız.
    private let bankB = BankCondition(name: "B", rateRule: .flat(.percent(45)))
    /// C: %40 NET ilan.
    private let bankC = BankCondition(name: "C", rateRule: .flat(.percent(40)), rateBasis: .net)

    private var withholding: WithholdingRule { .single(.percent(d("17.5"))) }

    private func table(_ conditions: [BankCondition], start: Weekday = .monday) -> [[InterestResult]] {
        CompareCalculator.projections(balance: d("100000"), conditions: conditions,
                                      withholding: withholding, startWeekday: start)
    }

    @Test("Vadeler sabit: 1, 7, 30, 90, 365 gün")
    func horizons() {
        #expect(CompareCalculator.horizons == [1, 7, 30, 90, 365])
    }

    @Test("Her hücre doğrudan CompoundingEngine.project sonucuna eşit", .tags(.invariant))
    func matchesEngine() {
        let conditions = [bankA, bankB, bankC]
        let results = table(conditions, start: .wednesday)
        #expect(results.count == conditions.count)
        for (column, condition) in conditions.enumerated() {
            #expect(results[column].count == CompareCalculator.horizons.count)
            for (index, nights) in CompareCalculator.horizons.enumerated() {
                let direct = CompoundingEngine.project(
                    initialBalance: d("100000"), startWeekday: .wednesday, nights: nights,
                    condition: condition, withholding: withholding
                )
                #expect(results[column][index] == direct)
            }
        }
    }

    @Test("Pozitif oranda net kazanç vadeyle kesin artar; değişmezler tutar", .tags(.invariant))
    func monotonicAndInvariant() {
        for row in table([bankA, bankB, bankC], start: .friday) {
            for result in row { assertInvariants(result) }
            let nets = row.map(\.netInterest)
            #expect(zip(nets, nets.dropFirst()).allSatisfy { $0 < $1 })
        }
    }

    @Test("1 günlük sonuç başlangıç gününden bağımsız (oran satırları buna dayanır)")
    func oneDayIndependentOfWeekday() {
        let monday = table([bankA, bankC], start: .monday)
        for start in Weekday.allCases {
            let other = table([bankA, bankC], start: start)
            #expect(other[0][0] == monday[0][0])
            #expect(other[1][0] == monday[1][0])
        }
    }

    @Test("Golden · 1 gün: A 91,54, B 101,71 → B en yüksek, A 10,17 geride", .tags(.golden))
    func goldenTwoBanks() {
        let results = table([bankA, bankB])
        let nets = results.map { $0[0].netInterest }
        #expect(nets == [d("91.54"), d("101.71")])
        #expect(CompareCalculator.rank(nets) == [
            CompareRank(isBest: false, shortfall: d("10.17")),
            CompareRank(isBest: true, shortfall: nil),
        ])
    }

    @Test("Golden · 1 gün: C (%40 net) 109,59 ile kazanır; B 7,88, A 18,05 geride", .tags(.golden))
    func goldenThreeBanks() {
        let results = table([bankA, bankB, bankC])
        let nets = results.map { $0[0].netInterest }
        #expect(nets == [d("91.54"), d("101.71"), d("109.59")])
        #expect(CompareCalculator.rank(nets) == [
            CompareRank(isBest: false, shortfall: d("18.05")),
            CompareRank(isBest: false, shortfall: d("7.88")),
            CompareRank(isBest: true, shortfall: nil),
        ])
    }

    @Test("Sıralama · eşit en yüksekler birlikte rozet alır")
    func rankTiedTop() {
        #expect(CompareCalculator.rank([d("5"), d("5"), d("3")]) == [
            CompareRank(isBest: true, shortfall: nil),
            CompareRank(isBest: true, shortfall: nil),
            CompareRank(isBest: false, shortfall: d("2")),
        ])
    }

    @Test("Sıralama · hepsi eşit ya da sıfırsa kimse rozet almaz", .tags(.edgeCase))
    func rankNoWinner() {
        let none = CompareRank(isBest: false, shortfall: nil)
        #expect(CompareCalculator.rank([d("5"), d("5")]) == [none, none])
        #expect(CompareCalculator.rank([0, 0, 0]) == [none, none, none])
        #expect(CompareCalculator.rank([]).isEmpty)
    }
}
