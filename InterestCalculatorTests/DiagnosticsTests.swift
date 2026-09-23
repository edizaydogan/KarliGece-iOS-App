//
//  DiagnosticsTests.swift
//  InterestCalculatorTests
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Tanılama ve Değişmezler")
struct DiagnosticsTests {

    private func condition(_ rate: Decimal = 45,
                           idle: IdleRequirement = .none) -> BankCondition {
        BankCondition(name: "x", rateRule: .flat(.percent(rate)), idleRequirement: idle)
    }

    @Test("Ciddiyet eşlemesi")
    func severityMapping() {
        #expect(CalculationDiagnostic.negativeBalanceClamped.severity == .error)
        #expect(CalculationDiagnostic.idlePercentageAboveOneHundred.severity == .error)
        #expect(CalculationDiagnostic.deductionRatesExceedTotal.severity == .error)
        #expect(CalculationDiagnostic.zeroBalance.severity == .warning)
        #expect(CalculationDiagnostic.belowMinimumBalance.severity == .warning)
        #expect(CalculationDiagnostic.zeroNights.severity == .info)
        #expect(CalculationDiagnostic.zeroWithholding.severity == .info)
    }

    @Test("Negatif girdiler kırpılır ve error tanılaması üretir")
    func negativeInputsClamped() {
        let r = InterestEngine.calculate(InterestInput(totalBalance: d("-100"), nights: -3,
            condition: BankCondition(name: "x", rateRule: .flat(.percent(-5))),
            withholding: .single(.percent(17.5))))
        #expect(r.diagnostics.contains(.negativeBalanceClamped))
        #expect(r.diagnostics.contains(.negativeNightsClamped))
        #expect(r.diagnostics.contains(.negativeRateClamped))
        #expect(r.totalBalance == 0)
        assertInvariants(r)
    }

    @Test("Vadesiz yüzdesi %100 üstü → clamp + error")
    func idleAboveHundred() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1,
            condition: condition(idle: .percentage(.percent(150))), withholdingPercent: 17.5))
        #expect(r.diagnostics.contains(.idlePercentageAboveOneHundred))
        #expect(r.idleAmount == d("100000"))   // %100'e kırpıldı
        assertInvariants(r)
    }

    @Test("Oran %200 üstü → clamp YOK, yalnız uyarı")
    func unusuallyHighRate() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1,
            condition: condition(250), withholdingPercent: 17.5))
        #expect(r.diagnostics.contains(.unusuallyHighRate))
        #expect(r.totalGrossInterest > 0)      // kırpılmadı
        assertInvariants(r)
    }

    @Test("Kesinti oranları toplamı %100 üstü → error")
    func deductionsExceedTotal() {
        let r = InterestEngine.calculate(InterestInput(totalBalance: d("100000"), nights: 1,
            condition: condition(), withholding: .single(.percent(150))))
        #expect(r.diagnostics.contains(.deductionRatesExceedTotal))
        assertInvariants(r)
    }

    @Test("Sıfır durum tanılamaları: stopaj/oran/gece/bakiye")
    func zeroDiagnostics() {
        let base = condition()
        let zeroWithholding = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1, condition: base, withholdingPercent: 0))
        #expect(zeroWithholding.diagnostics.contains(.zeroWithholding))
        #expect(zeroWithholding.netInterest == zeroWithholding.totalGrossInterest)

        let zeroRate = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1, condition: condition(0), withholdingPercent: 17.5))
        #expect(zeroRate.diagnostics.contains(.zeroRate))

        let zeroNights = InterestEngine.calculate(makeInput(total: d("100000"), nights: 0, condition: base, withholdingPercent: 17.5))
        #expect(zeroNights.diagnostics.contains(.zeroNights))

        let zeroBalance = InterestEngine.calculate(makeInput(total: 0, nights: 1, condition: base, withholdingPercent: 17.5))
        #expect(zeroBalance.diagnostics.contains(.zeroBalance))
    }

    @Test("Efektif oran: oran0 → 0 (nil değil); gece0/bakiye0 → nil")
    func effectiveNilRules() {
        let base = condition()
        let zeroRate = InterestEngine.calculate(makeInput(total: d("100000"), nights: 1, condition: condition(0), withholdingPercent: 17.5))
        #expect(zeroRate.grossEffectiveAnnualRate != nil)
        #expect(displayPercent(zeroRate.grossEffectiveAnnualRate) == 0)

        let zeroNights = InterestEngine.calculate(makeInput(total: d("100000"), nights: 0, condition: base, withholdingPercent: 17.5))
        #expect(zeroNights.grossEffectiveAnnualRate == nil)
        #expect(zeroNights.netEffectiveAnnualRate == nil)

        let zeroBalance = InterestEngine.calculate(makeInput(total: 0, nights: 1, condition: base, withholdingPercent: 17.5))
        #expect(zeroBalance.grossEffectiveAnnualRate == nil)
    }

    @Test("blockingIssues yalnız .error toplar")
    func blockingIssuesFiltersErrors() {
        let r = InterestEngine.calculate(makeInput(total: d("100000"), nights: 0, condition: condition(), withholdingPercent: 17.5))
        // gece 0 (info) + stopaj var → bloklayıcı olmamalı
        #expect(r.blockingIssues.isEmpty)
        let bad = InterestEngine.calculate(InterestInput(totalBalance: d("-1"), nights: 1, condition: condition(), withholding: .single(.percent(17.5))))
        #expect(!bad.blockingIssues.isEmpty)
        #expect(bad.blockingIssues.allSatisfy { $0.severity == .error })
    }

    // NaN yasağı — motorun "toplam fonksiyon" garantisi buna bağlı.
    @Test("Hiçbir sonuç alanı NaN değil (batarya)", .tags(.invariant))
    func noNaNInAnyResultField() {
        let conditions: [BankCondition] = [
            condition(),
            condition(0),
            condition(idle: .percentage(.percent(10))),
            condition(idle: .fixedAmount(d("5000"))),
            condition(idle: .tiered(cliffIdleTable())),
            BankCondition(name: "net", rateRule: .flat(.percent(45)), rateBasis: .net, idleRequirement: .percentage(.percent(10))),
            BankCondition(name: "cap", rateRule: .flat(.percent(45)), maxInterestBearingAmount: 0),
        ]
        let totals = [d("0"), d("1"), d("1000.05"), d("100000"), d("900000000000")]
        let nightsList = [0, 1, 3, 30]
        let withholdings: [WithholdingRule] = [.none, .single(.percent(0)), .single(.percent(17.5)), .single(.percent(100))]

        for c in conditions {
            for total in totals {
                for n in nightsList {
                    for w in withholdings {
                        let r = InterestEngine.calculate(InterestInput(totalBalance: total, nights: n, condition: c, withholding: w))
                        #expect(!r.totalGrossInterest.isNaN)
                        #expect(!r.netInterest.isNaN)
                        #expect(!r.totalDeductions.isNaN)
                        #expect(!r.idleAmount.isNaN)
                        #expect(!r.interestBearingBalance.isNaN)
                        #expect(!r.excessAboveCap.isNaN)
                        #expect(!(r.grossEffectiveAnnualRate?.fraction.isNaN ?? false))
                        #expect(!(r.netEffectiveAnnualRate?.fraction.isNaN ?? false))
                        // aynı anda temel değişmezler
                        #expect(r.idleAmount + r.interestBearingBalance + r.excessAboveCap == r.totalBalance)
                        #expect(r.netInterest + r.totalDeductions == r.totalGrossInterest)
                    }
                }
            }
        }
    }
}
