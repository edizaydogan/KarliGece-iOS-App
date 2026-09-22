//
//  TierSummaryText.swift
//  InterestCalculator
//
//  Kademeli kuralın düz Türkçe özeti. Bu cümleyi PRESENTATION üretir, motor değil.
//

import Foundation

enum TierSummaryText {
    /// Normalize edilmiş tablodan "50.000 ₺'nin altı → 5.000 ₺ vadesiz / ..." üretir.
    static func summary(for table: TierTable<TierRequirement>) -> String {
        table.tiers.enumerated().map { index, tier in
            let lower = index > 0 ? table.tiers[index - 1].upperBound : nil
            return "\(rangeText(lower: lower, upper: tier.upperBound)) → \(requirementText(tier.value))"
        }
        .joined(separator: " / ")
    }

    private static func rangeText(lower: Money?, upper: Money?) -> String {
        switch (lower, upper) {
        case (nil, let upper?):        return "\(money(upper)) ₺'nin altı"
        case (let lower?, let upper?): return "\(money(lower)) – \(money(upper)) ₺ arası"
        case (let lower?, nil):        return "\(money(lower)) ₺ ve üzeri"
        case (nil, nil):               return "Her tutar"
        }
    }

    private static func requirementText(_ requirement: TierRequirement) -> String {
        switch requirement {
        case .fixedAmount(let amount): return "\(money(amount)) ₺ vadesiz"
        case .percentage(let pct):     return "%\(pct.percentValue.grouped(fractionDigits: 0...2)) vadesiz"
        }
    }

    private static func money(_ value: Money) -> String {
        value.grouped(fractionDigits: 0)
    }
}
