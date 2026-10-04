//
//  MaxPlanText.swift
//  InterestCalculator
//
//  Max planının düz cümleleri (vadesiz kuralı, kademe, oran başlığı), seçilen
//  dilde. Planlayıcı metin üretmez; cümleyi Presentation kurar.
//

import Foundation

enum MaxPlanText {

    /// Tahsisin kuralı: kademeliyse "25.000 ₺'nin altı → vadesiz yok",
    /// değilse "%10 vadesiz" / "5.000 ₺ vadesiz" / "Vadesiz şartı yok".
    static func rule(for allocation: MaxPlan.Allocation, locale: Locale) -> String {
        guard let tier = allocation.tier else {
            return requirement(allocation.idleRule, locale: locale) ?? locale.localized("Vadesiz şartı yok")
        }
        let range = TierSummaryText.rangeText(lower: tier.lowerBound, upper: tier.upperBound, locale: locale)
        return "\(range) → \(requirement(allocation.idleRule, locale: locale) ?? locale.localized("vadesiz yok"))"
    }

    /// İlan edilen oran ve tabanı: "%42 · brüt".
    static func rateCaption(percent: Decimal, isNet: Bool, locale: Locale) -> String {
        let rate = percent.percentText(fractionDigits: 0...2, locale: locale)
        return isNet ? locale.localized("\(rate) · net") : locale.localized("\(rate) · brüt")
    }

    /// Para ayrılmayan bankanın başlığı: "%42 · brüt", EFT ücreti varsa
    /// "%42 · brüt · EFT 7,5 ₺".
    static func caption(for bank: MaxPlan.BankRef, locale: Locale) -> String {
        let rate = rateCaption(percent: bank.annualRatePercent, isNet: bank.rateIsNet, locale: locale)
        guard let fee = bank.eftFee, fee > 0 else { return rate }
        // Kırılmaz boşluk: "EFT", tutar ve "₺" ayrı satırlara düşmesin.
        return locale.localized("\(rate) · EFT\u{00A0}\(fee.grouped(fractionDigits: 0...2, locale: locale))\u{00A0}₺")
    }

    /// Şart cümlesi; şart yoksa (ya da sıfırsa) nil.
    private static func requirement(_ rule: MaxPlan.IdleRule, locale: Locale) -> String? {
        switch rule {
        case .none:
            return nil
        case .percentage(let percent):
            return percent > 0
                ? locale.localized("\(percent.percentText(fractionDigits: 0...2, locale: locale)) vadesiz")
                : nil
        case .fixedAmount(let amount):
            // Kırılmaz boşluk: dar kartta "10.000" ile "₺" ayrı satıra düşmesin.
            return amount > 0
                ? locale.localized("\(amount.grouped(fractionDigits: 0, locale: locale))\u{00A0}₺ vadesiz")
                : nil
        }
    }
}
