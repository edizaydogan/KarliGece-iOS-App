//
//  InterestEngine.swift
//  InterestCalculator
//
//  Tek saf, deterministik, TOPLAM fonksiyon. Throw etmez, fatalError atmaz,
//  NaN üretmez. String/Locale/Date/NumberFormatter kullanmaz.
//

import Foundation

nonisolated enum InterestEngine {

    /// Efektif oran hesabında DAİMA 365 takvim günü kullanılır (dayCountBasis'ten
    /// bağımsız) — bankalar arası karşılaştırılabilirlik için.
    private static let calendarDaysInYear: Decimal = 365

    /// Saf, deterministik, TOPLAM fonksiyon: her girdide anlamlı bir sonuç döner.
    static func calculate(_ rawInput: InterestInput) -> InterestResult {
        let rounding = RoundingPolicy.standard

        // 0. NORMALIZE — ham girdiyi güvenli aralığa çek.
        let (input, sanitizeDiagnostics) = rawInput.sanitized()
        var diagnostics = sanitizeDiagnostics

        // 1-4. Bakiye kovaları (uygunluk → kademe → vadesiz → cap).
        let (breakdown, breakdownDiagnostics) = BalanceBreakdown.make(
            totalBalance: input.totalBalance,
            condition: input.condition
        )
        diagnostics.append(contentsOf: breakdownDiagnostics)

        let days = Decimal(input.condition.dayCountBasis.daysInYear)   // >= 1
        let nights = Decimal(input.nights)                              // >= 0
        let bearing = breakdown.interestBearingBalance
        let idle = breakdown.idleAmount

        let rateFraction: Decimal
        switch input.condition.rateRule {
        case .flat(let percentage):
            rateFraction = percentage.fraction
        }
        let idleRateFraction = input.condition.idleAnnualRate.fraction
        let withholdingFraction = input.withholding.lines.reduce(Decimal(0)) { $0 + $1.rate.fraction }

        // Çarpmalar önce, bölme sonda; payda daima > 0 (days >= 1).
        let bearingRaw = safeDivide(bearing * rateFraction * nights, by: days)
        let idleRaw = safeDivide(idle * idleRateFraction * nights, by: days)

        // 5-6. FAIZ + VERGI — ilan tabanına göre.
        let grossOnBearing: Money
        let grossOnIdle: Money
        let totalGross: Money
        let totalDeductions: Money
        let net: Money

        switch input.condition.rateBasis {
        case .gross:
            // İlan edilen oran brüt: faizi hesapla, üstüne stopajı uygula.
            grossOnBearing = rounding.round2(bearingRaw)
            grossOnIdle = rounding.round2(idleRaw)
            totalGross = grossOnBearing + grossOnIdle
            var deductions: Money = 0
            for line in input.withholding.lines {
                deductions += rounding.round2(totalGross * line.rate.fraction)
            }
            totalDeductions = deductions
            net = totalGross - totalDeductions

        case .net:
            // İlan edilen oran net: faiz net kazancı verir, brütü geri hesapla.
            net = rounding.round2(bearingRaw + idleRaw)
            let grossingDenominator = Decimal(1) - withholdingFraction
            if grossingDenominator > 0 {
                grossOnBearing = rounding.round2(safeDivide(bearingRaw, by: grossingDenominator))
                grossOnIdle = rounding.round2(safeDivide(idleRaw, by: grossingDenominator))
                totalGross = grossOnBearing + grossOnIdle
            } else {
                // %100+ stopaj: brüte çevirmek tanımsız (.deductionRatesExceedTotal
                // zaten üretildi). Kesinti gösterme, negatif tutar üretme.
                grossOnBearing = net
                grossOnIdle = 0
                totalGross = net
            }
            totalDeductions = totalGross - net
        }

        if withholdingFraction == 0 {
            diagnostics.append(.zeroWithholding)
        }

        // 7. EFEKTIF — yıllık basit getiri, TOPLAM bakiye üzerinden, daima 365 gün.
        let grossEffective: Percentage?
        let netEffective: Percentage?
        let annualBase = input.totalBalance * nights
        if input.totalBalance > 0 && input.nights > 0 && annualBase > 0 {
            grossEffective = .percent(totalGross * calendarDaysInYear * 100 / annualBase)
            netEffective = .percent(net * calendarDaysInYear * 100 / annualBase)
        } else {
            grossEffective = nil
            netEffective = nil
        }

        return InterestResult(
            breakdown: breakdown,
            grossInterestOnBearing: grossOnBearing,
            grossInterestOnIdle: grossOnIdle,
            totalGrossInterest: totalGross,
            totalDeductions: totalDeductions,
            netInterest: net,
            grossEffectiveAnnualRate: grossEffective,
            netEffectiveAnnualRate: netEffective,
            diagnostics: diagnostics
        )
    }

    /// Korumalı bölme: payda `> 0` değilse `0` döner. `Decimal(0)/Decimal(0)`
    /// sessizce NaN ürettiği için motorda korumasız bölme YOKTUR.
    private static func safeDivide(_ numerator: Money, by denominator: Money) -> Money {
        denominator > 0 ? numerator / denominator : 0
    }
}
