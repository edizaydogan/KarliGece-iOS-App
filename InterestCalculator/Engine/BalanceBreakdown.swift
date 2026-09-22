//
//  BalanceBreakdown.swift
//  InterestCalculator
//
//  Toplam bakiyenin üç kovaya ayrılması: vadesiz kalan, faize giren, limit üstü.
//  Saf fonksiyon; metin üretmez. Zincir: uygunluk -> kademe -> vadesiz -> cap.
//

import Foundation

/// Kademeli vadesiz şartında seçilen kademenin yapısal tanımı. Presentation
/// katmanı bundan "50.000 ₺'nin altı → 5.000 ₺ vadesiz" gibi cümleyi üretir.
nonisolated struct AppliedTier: Hashable, Sendable {
    var index: Int
    /// Türetilmiş alt sınır (bir önceki kademenin üst sınırı); ilk kademede nil.
    var lowerBound: Money?
    /// Bu kademenin üst sınırı; son/sınırsız kademede nil.
    var upperBound: Money?
    var requirement: TierRequirement
}

/// Toplam bakiyenin faiz hesabı öncesi üç kovaya bölünmüş hali.
///
/// Değişmez (her sonuçta, uygun olmayan dal dahil):
/// `idleAmount + interestBearingBalance + excessAboveCap == totalBalance`.
/// Bu, `interestBearingBalance`'in daima FARK olarak türetilmesiyle sağlanır —
/// vadesiz tutar yuvarlanır, faize giren `total − idle` ile bulunur.
nonisolated struct BalanceBreakdown: Hashable, Sendable {
    var totalBalance: Money
    var idleAmount: Money
    var interestBearingBalance: Money
    var excessAboveCap: Money
    /// Yalnız kademeli vadesiz şartında dolu.
    var appliedTier: AppliedTier?

    /// Bakiye kovalarını üreten saf fonksiyon. `totalBalance` sanitize edilmiş
    /// (>= 0) varsayılır. Üretilen tanılamalar ayrıca döner.
    static func make(
        totalBalance total: Money,
        condition: BankCondition
    ) -> (breakdown: BalanceBreakdown, diagnostics: [CalculationDiagnostic]) {
        var diagnostics: [CalculationDiagnostic] = []

        // 1. UYGUNLUK — en az bakiye şartı karşılanmıyorsa faiz işlemez.
        if let minBalance = condition.minTotalBalance, total < minBalance {
            diagnostics.append(.belowMinimumBalance)
            let breakdown = BalanceBreakdown(
                totalBalance: total,
                idleAmount: total,
                interestBearingBalance: 0,
                excessAboveCap: 0,
                appliedTier: nil
            )
            return (breakdown, diagnostics)
        }

        // 2. KADEME + 3. VADESIZ — gereken vadesiz tutar (idleRequired) hesaplanır.
        //    Yüzde şartının tabanı DAİMA toplam bakiyedir.
        var idleRequired: Money = 0
        var appliedTier: AppliedTier?

        switch condition.idleRequirement {
        case .none:
            idleRequired = 0

        case .percentage(let percentage):
            if percentage.percentValue > 100 {
                diagnostics.append(.idlePercentageAboveOneHundred)
            }
            idleRequired = percentage.clampedToZeroThroughOneHundred().applied(to: total)

        case .fixedAmount(let amount):
            idleRequired = max(0, amount)

        case .tiered(let table):
            // Tablo, kurulurken ürettiği normalizasyon tanılamalarını taşır.
            diagnostics.append(contentsOf: table.normalizationDiagnostics)
            // Kademe TOPLAM BAKİYE üzerinden seçilir (üst sınır DIŞLAYICI).
            let match = table.resolve(for: total)
            let lowerBound = match.index > 0 ? table.tiers[match.index - 1].upperBound : nil
            appliedTier = AppliedTier(
                index: match.index,
                lowerBound: lowerBound,
                upperBound: match.tier.upperBound,
                requirement: match.tier.value
            )
            switch match.tier.value {
            case .percentage(let percentage):
                if percentage.percentValue > 100 {
                    diagnostics.append(.idlePercentageAboveOneHundred)
                }
                idleRequired = percentage.clampedToZeroThroughOneHundred().applied(to: total)
            case .fixedAmount(let amount):
                idleRequired = max(0, amount)
            }
        }

        // Vadesiz tutar yuvarlanır (parçalardan biri daima yuvarlanır).
        idleRequired = RoundingPolicy.standard.round2(idleRequired)

        // Şart toplam bakiyeyi aşıyorsa bakiyeye çekilir; faize giren 0 olur.
        let idle: Money
        if idleRequired > total {
            idle = total
            diagnostics.append(.requirementConsumesEntireBalance)
        } else {
            idle = idleRequired
        }

        // 4. ÜST LIMIT — faize giren FARK olarak türetilir: candidate = total − idle.
        let candidate = total - idle
        var interestBearing = candidate
        var excess: Money = 0
        if let cap = condition.maxInterestBearingAmount {
            let safeCap = max(0, cap)
            if candidate > safeCap {
                interestBearing = safeCap
                excess = candidate - safeCap
                diagnostics.append(.cappedInterestBearingAmount)
            }
        }

        let breakdown = BalanceBreakdown(
            totalBalance: total,
            idleAmount: idle,
            interestBearingBalance: interestBearing,
            excessAboveCap: excess,
            appliedTier: appliedTier
        )
        return (breakdown, diagnostics)
    }
}
