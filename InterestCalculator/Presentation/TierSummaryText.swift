//
//  TierSummaryText.swift
//  InterestCalculator
//
//  Kademeli kuralın düz özeti, seçilen dilde. Bu cümleyi PRESENTATION üretir,
//  motor değil.
//

import Foundation

enum TierSummaryText {
    /// Normalize edilmiş tablodan "50.000 ₺'nin altı → 5.000 ₺ vadesiz / ..." üretir.
    static func summary(for table: TierTable<TierRequirement>, locale: Locale) -> String {
        table.tiers.enumerated().map { index, tier in
            let lower = index > 0 ? table.tiers[index - 1].upperBound : nil
            return "\(rangeText(lower: lower, upper: tier.upperBound, locale: locale)) → \(requirementText(tier.value, locale: locale))"
        }
        .joined(separator: " / ")
    }

    /// Bir kademenin aralığı: "50.000 ₺'nin altı", "25.000 – 50.000 ₺ arası",
    /// "50.000 ₺ ve üzeri". Max detayı ve Özet'in kademe rozeti de kullanır.
    static func rangeText(lower: Money?, upper: Money?, locale: Locale) -> String {
        switch (lower, upper) {
        case (nil, let upper?):
            return locale.localized("\(money(upper, locale)) ₺'nin altı")
        case (let lower?, let upper?):
            return locale.localized("\(money(lower, locale)) – \(money(upper, locale)) ₺ arası")
        case (let lower?, nil):
            return locale.localized("\(money(lower, locale)) ₺ ve üzeri")
        case (nil, nil):
            return locale.localized("Her tutar")
        }
    }

    /// Kademenin vadesiz şartı: "5.000 ₺ vadesiz", "%10 vadesiz".
    static func requirementText(_ requirement: TierRequirement, locale: Locale) -> String {
        switch requirement {
        case .fixedAmount(let amount):
            return locale.localized("\(money(amount, locale)) ₺ vadesiz")
        case .percentage(let pct):
            return locale.localized("\(pct.percentValue.percentText(fractionDigits: 0...2, locale: locale)) vadesiz")
        }
    }

    private static func money(_ value: Money, _ locale: Locale) -> String {
        value.grouped(fractionDigits: 0, locale: locale)
    }
}
