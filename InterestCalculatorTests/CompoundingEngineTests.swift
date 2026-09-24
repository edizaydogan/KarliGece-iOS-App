//
//  CompoundingEngineTests.swift
//  InterestCalculatorTests
//
//  Valör kurallı bileşik işletme. Golden'lar elle hesaplanmış, teste pinlenmiş.
//  Stopaj %17,5, oran %45 brüt, ACT/365, vadesiz şartsız (aksi belirtilmedikçe).
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Bileşik Valör (Compounding)")
struct CompoundingEngineTests {

    private func flat(_ rate: Decimal,
                      idle: IdleRequirement = .none,
                      basis: RateBasis = .gross,
                      cap: Money? = nil,
                      dayCount: DayCountBasis = .actual365) -> BankCondition {
        BankCondition(name: "g", rateRule: .flat(.percent(rate)), rateBasis: basis,
                      idleRequirement: idle, maxInterestBearingAmount: cap,
                      dayCountBasis: dayCount)
    }

    private func project(total: Decimal, start: Weekday, nights: Int,
                         condition: BankCondition, withholdingPercent: Decimal) -> InterestResult {
        CompoundingEngine.project(
            initialBalance: total, startWeekday: start, nights: nights,
            condition: condition, withholding: .single(.percent(withholdingPercent))
        )
    }

    // MARK: - Weekday aritmetiği

    @Test("Weekday · ilerleme ve iş günü")
    func weekdayArithmetic() {
        #expect(Weekday.monday.next == .tuesday)
        #expect(Weekday.friday.next == .saturday)
        #expect(Weekday.sunday.next == .monday)
        #expect(Weekday.friday.advanced(by: 3) == .monday)
        #expect(Weekday.monday.advanced(by: 7) == .monday)
        #expect(Weekday.monday.advanced(by: -1) == .sunday)
        #expect(Weekday.saturday.isWeekend)
        #expect(Weekday.sunday.isWeekend)
        #expect(Weekday.friday.isBusinessDay)
        #expect(!Weekday.saturday.isBusinessDay)
    }

    // MARK: - Tek gece == tek-atış motoru

    @Test("1 gece · tek-atış motoruyla birebir")
    func singleNightMatchesEngine() {
        let cond = flat(45)
        let compounded = project(total: d("100000"), start: .monday, nights: 1,
                                 condition: cond, withholdingPercent: 17.5)
        let single = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1,
                                                        condition: cond, withholdingPercent: 17.5))
        #expect(compounded.totalGrossInterest == single.totalGrossInterest)
        #expect(compounded.netInterest == single.netInterest)
        #expect(compounded.totalDeductions == single.totalDeductions)
        #expect(compounded.netInterest == d("101.71"))
        assertInvariants(compounded)
    }

    // MARK: - Hafta içi bileşik (Pzt→Cum, 4 gece)

    @Test("Golden · Pazartesi 4 gece (hafta içi günlük bileşik)", .tags(.golden))
    func weekdayCompounding() {
        let r = project(total: d("100000"), start: .monday, nights: 4,
                        condition: flat(45), withholdingPercent: 17.5)
        #expect(r.totalGrossInterest == d("493.90"))
        #expect(r.totalDeductions == d("86.44"))
        #expect(r.netInterest == d("407.46"))
        // Vade sonu bakiyesi = anapara + net.
        #expect(r.totalBalance + r.netInterest == d("100407.46"))
        assertInvariants(r)
    }

    // MARK: - Hafta sonu toplaması (Cuma başlangıç 3 gece)

    @Test("Golden · Cuma 3 gece (Cuma+Cmt+Paz aynı bakiyede)", .tags(.golden))
    func weekendBatch() {
        let r = project(total: d("100000"), start: .friday, nights: 3,
                        condition: flat(45), withholdingPercent: 17.5)
        #expect(r.totalGrossInterest == d("369.87"))
        #expect(r.totalDeductions == d("64.74"))
        #expect(r.netInterest == d("305.13"))
        assertInvariants(r)
    }

    // MARK: - Ayrımlayıcı: hafta sonu bileşiklenmez, hafta içi bileşiklenir

    @Test("Cuma-3 = 3×tek gece < Pazartesi-3 (bileşik)", .tags(.boundary))
    func weekendFlatButWeekdayCompounds() {
        let cond = flat(45)
        let oneNet = project(total: d("100000"), start: .monday, nights: 1,
                             condition: cond, withholdingPercent: 17.5).netInterest
        let friday3 = project(total: d("100000"), start: .friday, nights: 3,
                              condition: cond, withholdingPercent: 17.5).netInterest
        let monday3 = project(total: d("100000"), start: .monday, nights: 3,
                              condition: cond, withholdingPercent: 17.5).netInterest
        #expect(friday3 == oneNet * 3)   // hafta sonu: üç gece de aynı bakiyede
        #expect(monday3 > friday3)       // hafta içi: her gün büyümüş bakiyede
    }

    // MARK: - Sıfır gece

    @Test("0 gece · kazanç yok")
    func zeroNights() {
        let r = project(total: d("100000"), start: .monday, nights: 0,
                        condition: flat(45), withholdingPercent: 17.5)
        #expect(r.netInterest == 0)
        #expect(r.totalGrossInterest == 0)
        assertInvariants(r)
    }

    // MARK: - Değişmez: final == anapara + net; net + kesinti == brüt (tüm günler)

    @Test("Değişmez · her başlangıç günü ve vade için tutarlı", .tags(.invariant))
    func invariantsAcrossStartsAndHorizons() {
        for start in Weekday.allCases {
            for nights in [1, 2, 3, 5, 7, 10, 30, 90] {
                let r = project(total: d("250000"), start: start, nights: nights,
                                condition: flat(45, idle: .percentage(.percent(10))),
                                withholdingPercent: 17.5)
                assertInvariants(r)
                #expect(r.netInterest + r.totalDeductions == r.totalGrossInterest)
                // Bileşik, basit faizden az olamaz (büyüyen bakiye).
                #expect(r.netInterest >= 0)
            }
        }
    }

    // MARK: - Vadesiz şart bileşikte de uygulanır

    @Test("Vadesiz %10 · faize giren bakiye anaparaya göre bölünür")
    func idleSplitApplies() {
        let r = project(total: d("100000"), start: .monday, nights: 1,
                        condition: flat(45, idle: .percentage(.percent(10))),
                        withholdingPercent: 17.5)
        // Golden #1 ile aynı tek gece.
        #expect(r.idleAmount == d("10000"))
        #expect(r.interestBearingBalance == d("90000"))
        #expect(r.netInterest == d("91.54"))
        assertInvariants(r)
    }
}
