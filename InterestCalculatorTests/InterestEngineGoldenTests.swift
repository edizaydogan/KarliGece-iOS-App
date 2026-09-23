//
//  InterestEngineGoldenTests.swift
//  InterestCalculatorTests
//
//  Elle hesaplanmış, teste pinlenmiş uçtan uca değerler. Stopaj %17,5.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Uçtan Uca (Golden)", .tags(.golden))
struct InterestEngineGoldenTests {

    private func flat(_ rate: Decimal,
                      idle: IdleRequirement = .none,
                      basis: RateBasis = .gross,
                      cap: Money? = nil,
                      dayCount: DayCountBasis = .actual365) -> BankCondition {
        BankCondition(name: "g", rateRule: .flat(.percent(rate)), rateBasis: basis,
                      idleRequirement: idle, maxInterestBearingAmount: cap,
                      dayCountBasis: dayCount)
    }

    @Test("Golden #1 — ana örnek")
    func golden1() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1,
                                                   condition: flat(45, idle: .percentage(.percent(10))),
                                                   withholdingPercent: 17.5))
        #expect(r.idleAmount == d("10000"))
        #expect(r.interestBearingBalance == d("90000"))
        #expect(r.totalGrossInterest == d("110.96"))
        #expect(r.totalDeductions == d("19.42"))
        #expect(r.netInterest == d("91.54"))
        expectClose(r.grossEffectiveAnnualRate!.percentValue, d("40.5004"))
        expectClose(r.netEffectiveAnnualRate!.percentValue, d("33.4121"))
        #expect(displayPercent(r.grossEffectiveAnnualRate) == d("40.50"))
        #expect(displayPercent(r.netEffectiveAnnualRate) == d("33.41"))
        assertInvariants(r)
    }

    @Test("Golden #2 — 3 gece")
    func golden2() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 3,
                                                   condition: flat(45, idle: .percentage(.percent(10))),
                                                   withholdingPercent: 17.5))
        #expect(r.totalGrossInterest == d("332.88"))
        #expect(r.totalDeductions == d("58.25"))
        #expect(r.netInterest == d("274.63"))
        assertInvariants(r)
    }

    @Test("Golden #3 — ACT/360")
    func golden3() {
        let r = InterestEngine.calculate(makeInput(total: d("90000"), nights: 1,
                                                   condition: flat(45, dayCount: .actual360),
                                                   withholdingPercent: 17.5))
        #expect(r.totalGrossInterest == d("112.50"))
        #expect(r.totalDeductions == d("19.69"))
        #expect(r.netInterest == d("92.81"))
        assertInvariants(r)
    }

    @Test("Golden #4 — cap 250.000")
    func golden4() {
        let r = InterestEngine.calculate(makeInput(total: d("400000"), nights: 1,
                                                   condition: flat(45, idle: .percentage(.percent(10)), cap: d("250000")),
                                                   withholdingPercent: 17.5))
        #expect(r.idleAmount == d("40000"))
        #expect(r.interestBearingBalance == d("250000"))
        #expect(r.excessAboveCap == d("110000"))
        #expect(r.totalGrossInterest == d("308.22"))
        #expect(r.netInterest == d("254.28"))
        #expect(displayPercent(r.netEffectiveAnnualRate) == d("23.20"))
        assertInvariants(r)
    }

    // Kademe uçurumu — en önemli regresyon üçlüsü (dışlayıcı sınır).
    @Test("Golden #5·6·7 — kademe uçurumu", .tags(.boundary))
    func goldenCliff() {
        let cond = BankCondition(name: "t", rateRule: .flat(.percent(45)),
                                 idleRequirement: .tiered(cliffIdleTable()))

        let r5 = InterestEngine.calculate(makeInput(total: d("50000"), nights: 1, condition: cond, withholdingPercent: 17.5))
        #expect(r5.idleAmount == d("10000"))          // tam 50.000 → üst kademe
        #expect(r5.interestBearingBalance == d("40000"))
        #expect(r5.totalGrossInterest == d("49.32"))
        #expect(r5.netInterest == d("40.69"))

        let r6 = InterestEngine.calculate(makeInput(total: d("49999.99"), nights: 1, condition: cond, withholdingPercent: 17.5))
        #expect(r6.idleAmount == d("5000"))           // alt kademe
        #expect(r6.interestBearingBalance == d("44999.99"))
        #expect(r6.totalGrossInterest == d("55.48"))
        #expect(r6.netInterest == d("45.77"))

        let r7 = InterestEngine.calculate(makeInput(total: d("50000.01"), nights: 1, condition: cond, withholdingPercent: 17.5))
        #expect(r7.idleAmount == d("10000"))          // üst kademe
        #expect(r7.interestBearingBalance == d("40000.01"))
        #expect(r7.netInterest == d("40.69"))

        assertInvariants(r5); assertInvariants(r6); assertInvariants(r7)
    }

    @Test("Golden #15 — net ilan tabanı")
    func golden15() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1,
                                                   condition: flat(45, idle: .percentage(.percent(10)), basis: .net),
                                                   withholdingPercent: 17.5))
        #expect(r.netInterest == d("110.96"))
        #expect(r.totalGrossInterest == d("134.50"))
        #expect(r.totalDeductions == d("23.54"))
        assertInvariants(r)
    }

    @Test("Golden #16 — şart yok")
    func golden16() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1,
                                                   condition: flat(45), withholdingPercent: 17.5))
        #expect(r.interestBearingBalance == d("100000"))
        #expect(r.totalGrossInterest == d("123.29"))
        #expect(r.netInterest == d("101.71"))
        assertInvariants(r)
    }

    @Test("Golden #17 — 900 milyar, taşma yok")
    func golden17() {
        let r = InterestEngine.calculate(InterestInput(totalBalance: d("900000000000"), nights: 1,
                                                       condition: flat(45), withholding: .none))
        #expect(r.totalGrossInterest == d("1109589041.10"))
        assertInvariants(r)
    }
}
