//
//  MaxPlanText.swift
//  InterestCalculator
//
//  Max planının düz Türkçe cümleleri (vadesiz kuralı, kademe, oran başlığı).
//  Planlayıcı metin üretmez; cümleyi Presentation kurar.
//

import Foundation

enum MaxPlanText {

    /// Tahsisin kuralı: kademeliyse "25.000 ₺'nin altı → vadesiz yok",
    /// değilse "%10 vadesiz" / "5.000 ₺ vadesiz" / "Vadesiz şartı yok".
    static func rule(for allocation: MaxPlan.Allocation) -> String {
        guard let tier = allocation.tier else {
            return requirement(allocation.idleRule) ?? "Vadesiz şartı yok"
        }
        let range = TierSummaryText.rangeText(lower: tier.lowerBound, upper: tier.upperBound)
        return "\(range) → \(requirement(allocation.idleRule) ?? "vadesiz yok")"
    }

    /// İlan edilen oran ve tabanı: "%42 · brüt".
    static func rateCaption(percent: Decimal, isNet: Bool) -> String {
        "%\(percent.grouped(fractionDigits: 0...2)) · \(isNet ? "net" : "brüt")"
    }

    /// Şart cümlesi; şart yoksa (ya da sıfırsa) nil.
    private static func requirement(_ rule: MaxPlan.IdleRule) -> String? {
        switch rule {
        case .none:
            return nil
        case .percentage(let percent):
            return percent > 0 ? "%\(percent.grouped(fractionDigits: 0...2)) vadesiz" : nil
        case .fixedAmount(let amount):
            // Kırılmaz boşluk: dar kartta "10.000" ile "₺" ayrı satıra düşmesin.
            return amount > 0 ? "\(amount.grouped(fractionDigits: 0))\u{00A0}₺ vadesiz" : nil
        }
    }
}
