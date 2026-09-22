//
//  InterestInput.swift
//  InterestCalculator
//
//  Motorun tek girdisi. Ham değerleri güvenli aralığa çeken `sanitized()`
//  girdi temizleme adımını (hesap zincirinin 0. adımı) burada tutar.
//

import Foundation

/// Motorun tek girdisi. Toplam bakiye ve gece sayısı tüm bankalar için ortaktır;
/// stopaj da (vergi olduğu için) bankaya değil girdiye bağlıdır.
nonisolated struct InterestInput: Hashable, Sendable {
    var totalBalance: Money
    var nights: Int
    var condition: BankCondition
    var withholding: WithholdingRule

    init(
        totalBalance: Money,
        nights: Int,
        condition: BankCondition,
        withholding: WithholdingRule
    ) {
        self.totalBalance = totalBalance
        self.nights = nights
        self.condition = condition
        self.withholding = withholding
    }

    /// Girdiyi güvenli aralığa çeker ve her kırpma için bir tanılama üretir.
    /// Faiz oranı %100'ü aşabildiği için ÜST sınıra çekilmez; yalnız negatifi
    /// sıfıra çekilir. %200 üstü sadece uyarı üretir (kullanıcı günlük oran
    /// girmiş olabilir).
    func sanitized() -> (input: InterestInput, diagnostics: [CalculationDiagnostic]) {
        var diagnostics: [CalculationDiagnostic] = []

        // Gece sayısı
        var cleanNights = nights
        if nights < 0 {
            cleanNights = 0
            diagnostics.append(.negativeNightsClamped)
        } else if nights == 0 {
            diagnostics.append(.zeroNights)
        }

        // Toplam bakiye
        var cleanBalance = totalBalance
        if totalBalance < 0 {
            cleanBalance = 0
            diagnostics.append(.negativeBalanceClamped)
        } else if totalBalance == 0 {
            diagnostics.append(.zeroBalance)
        }

        // Faiz oranı (yalnız negatifi kırp; üst sınır yok)
        var cleanCondition = condition
        switch condition.rateRule {
        case .flat(let rate):
            let clamped = rate.clampedToNonNegative()
            if rate.fraction < 0 {
                diagnostics.append(.negativeRateClamped)
            } else if rate.fraction == 0 {
                diagnostics.append(.zeroRate)
            }
            if clamped.percentValue > 200 {
                diagnostics.append(.unusuallyHighRate)
            }
            cleanCondition.rateRule = .flat(clamped)
        }

        // Stopaj satırları: her biri [%0, %100]; toplam %100'ü aşarsa hata
        var cleanWithholding = withholding
        var sumPercent: Decimal = 0
        var clampedLines: [WithholdingRule.Line] = []
        for line in withholding.lines {
            sumPercent += line.rate.percentValue
            clampedLines.append(WithholdingRule.Line(rate: line.rate.clampedToZeroThroughOneHundred()))
        }
        cleanWithholding.lines = clampedLines
        if sumPercent > 100 {
            diagnostics.append(.deductionRatesExceedTotal)
        }

        let cleaned = InterestInput(
            totalBalance: cleanBalance,
            nights: cleanNights,
            condition: cleanCondition,
            withholding: cleanWithholding
        )
        return (cleaned, diagnostics)
    }
}
