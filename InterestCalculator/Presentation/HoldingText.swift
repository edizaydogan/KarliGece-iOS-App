//
//  HoldingText.swift
//  InterestCalculator
//
//  Bakiyelerim'in düz Türkçe metinleri (oran başlığı, koşul özeti, hareket
//  başlığı, tarih ve işaretli tutar). Defter metin üretmez; cümleyi
//  Presentation kurar.
//

import Foundation

enum HoldingText {

    /// İlan edilen oran ve tabanı: "%45 · brüt"; oran yoksa "Oran girilmemiş".
    static func rateCaption(for bank: BankConditionDraft) -> String {
        guard let rate = DecimalInputParser.parse(bank.annualRateText), rate > 0 else {
            return "Oran girilmemiş"
        }
        return MaxPlanText.rateCaption(percent: rate, isNet: bank.rateBasis == .net)
    }

    /// Faizin işlediği koşullar: "%45 · brüt · %10 vadesiz · stopaj %17,5".
    static func conditionSummary(for bank: BankConditionDraft, withholdingText: String) -> String {
        var parts = [rateCaption(for: bank)]
        switch bank.idleKind {
        case .none:
            break
        case .percentage:
            if let percent = DecimalInputParser.parse(bank.idlePercentageText), percent > 0 {
                parts.append("%\(percent.grouped(fractionDigits: 0...2)) vadesiz")
            }
        case .fixedAmount:
            if let amount = DecimalInputParser.parse(bank.idleFixedAmountText), amount > 0 {
                // Kırılmaz boşluk: tutar ile "₺" ayrı satıra düşmesin.
                parts.append("\(amount.grouped(fractionDigits: 0))\u{00A0}₺ vadesiz")
            }
        case .tiered:
            parts.append("kademeli vadesiz")
        }
        let withholding = DecimalInputParser.parse(withholdingText) ?? 0
        parts.append("stopaj %\(withholding.grouped(fractionDigits: 0...2))")
        return parts.joined(separator: " · ")
    }

    /// Hareket başlığı: "Bakiye girildi", "Faiz", "Faiz · 3 gece".
    static func title(for entry: HoldingEntry) -> String {
        switch entry.kind {
        case .balanceSet:
            return "Bakiye girildi"
        case .interest(let nights):
            return nights == 1 ? "Faiz" : "Faiz · \(nights) gece"
        }
    }

    /// Gün: "6 Eki 2026 Pzt" (Locale.current).
    static func dayText(_ day: CalendarDay) -> String {
        AccrualCalendar.date(for: day)
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// İşaretli tutar: "+₺101,71", "-₺5.000,00"; sıfırda işaretsiz.
    static func signedMoney(_ value: Money) -> String {
        value.formatted(.currency(code: "TRY").sign(strategy: .always(showZero: false)))
    }
}
