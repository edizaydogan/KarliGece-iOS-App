//
//  InterestResult.swift
//  InterestCalculator
//
//  Motorun çıktısı. Şelalenin ihtiyaç duyduğu her sayıyı taşır; metin taşımaz.
//

import Foundation

/// `InterestEngine.calculate(_:)` sonucu. Tüm tutarlar 2 haneye yuvarlıdır;
/// efektif oranlar yuvarlanmamıştır (Presentation biçimlendirir).
///
/// Değişmezler (her sonuçta):
/// 1. `idleAmount + interestBearingBalance + excessAboveCap == totalBalance`
/// 2. `netInterest + totalDeductions == totalGrossInterest`
/// 3. Tüm tutarlar `>= 0`
/// 4. `interestBearingBalance <= totalBalance`
/// 5. Hiçbir alan `isNaN` değil
nonisolated struct InterestResult: Hashable, Sendable {
    var breakdown: BalanceBreakdown

    /// Faize giren bakiyeden gelen brüt faiz (2 haneye yuvarlı).
    var grossInterestOnBearing: Money
    /// Vadesiz kısma ödenen brüt faiz (`idleAnnualRate`; v1'de daima 0).
    var grossInterestOnIdle: Money
    var totalGrossInterest: Money
    var totalDeductions: Money
    var netInterest: Money

    /// Yıllık basit efektif getiri, TOPLAM bakiye üzerinden. `total > 0 && nights > 0`
    /// değilse `nil`. Yuvarlanmamış — daima 365 takvim günüyle hesaplanır.
    var grossEffectiveAnnualRate: Percentage?
    var netEffectiveAnnualRate: Percentage?

    var diagnostics: [CalculationDiagnostic]

    /// Sonucu bloklayan (`.error`) tanılamalar.
    var blockingIssues: [CalculationDiagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    // Şelale kolaylık erişimleri
    var totalBalance: Money { breakdown.totalBalance }
    var idleAmount: Money { breakdown.idleAmount }
    var interestBearingBalance: Money { breakdown.interestBearingBalance }
    var excessAboveCap: Money { breakdown.excessAboveCap }
}
