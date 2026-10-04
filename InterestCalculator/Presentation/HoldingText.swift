//
//  HoldingText.swift
//  InterestCalculator
//
//  Bakiyelerim'in düz metinleri (oran başlığı, koşul özeti, hareket başlığı,
//  tarih ve işaretli tutar), seçilen dilde. Defter metin üretmez; cümleyi
//  Presentation kurar.
//

import Foundation

enum HoldingText {

    /// İlan edilen oran ve tabanı: "%45 · brüt"; oran yoksa "Oran girilmemiş".
    static func rateCaption(for bank: BankConditionDraft, locale: Locale) -> String {
        guard let rate = DecimalInputParser.parse(bank.annualRateText), rate > 0 else {
            return locale.localized("Oran girilmemiş")
        }
        return MaxPlanText.rateCaption(percent: rate, isNet: bank.rateBasis == .net, locale: locale)
    }

    /// Faizin işlediği koşullar: "%45 · brüt · %10 vadesiz · stopaj %17,5".
    static func conditionSummary(for bank: BankConditionDraft, withholdingText: String, locale: Locale) -> String {
        var parts = [rateCaption(for: bank, locale: locale)]
        switch bank.idleKind {
        case .none:
            break
        case .percentage:
            if let percent = DecimalInputParser.parse(bank.idlePercentageText), percent > 0 {
                parts.append(locale.localized("\(percent.percentText(fractionDigits: 0...2, locale: locale)) vadesiz"))
            }
        case .fixedAmount:
            if let amount = DecimalInputParser.parse(bank.idleFixedAmountText), amount > 0 {
                // Kırılmaz boşluk: tutar ile "₺" ayrı satıra düşmesin.
                parts.append(locale.localized("\(amount.grouped(fractionDigits: 0, locale: locale))\u{00A0}₺ vadesiz"))
            }
        case .tiered:
            parts.append(locale.localized("kademeli vadesiz"))
        }
        let withholding = DecimalInputParser.parse(withholdingText) ?? 0
        parts.append(locale.localized("stopaj \(withholding.percentText(fractionDigits: 0...2, locale: locale))"))
        return parts.joined(separator: " · ")
    }

    /// Hareket başlığı: "Bakiye girildi", "Faiz", "Faiz · 3 gece".
    static func title(for entry: HoldingEntry, locale: Locale) -> String {
        switch entry.kind {
        case .balanceSet:
            return locale.localized("Bakiye girildi")
        case .interest(let nights):
            return nights == 1 ? locale.localized("Faiz") : locale.localized("Faiz · \(nights) gece")
        }
    }

    /// Gün: "6 Eki 2026 Pzt".
    static func dayText(_ day: CalendarDay, locale: Locale) -> String {
        AccrualCalendar.date(for: day)
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(locale))
    }

    /// İşaretli tutar: "+₺101,71", "-₺5.000,00"; sıfırda işaretsiz.
    static func signedMoney(_ value: Money, locale: Locale) -> String {
        value.formatted(.currency(code: "TRY").sign(strategy: .always(showZero: false)).locale(locale))
    }
}
