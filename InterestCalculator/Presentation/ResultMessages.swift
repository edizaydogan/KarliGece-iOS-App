//
//  ResultMessages.swift
//  InterestCalculator
//
//  Sonuç durum ve uyarı cümleleri. Özet ile Karşılaştır AYNI metni kullanır;
//  motor metin üretmez, cümleyi Presentation üretir. Renk seçimi görünümdedir
//  (renk tek başına anlam taşımaz).
//

import Foundation

enum ResultMessages {

    /// Tahmin / yatırım tavsiyesi uyarısı — Özet ve Karşılaştır'ın altında aynen.
    static func disclaimer(_ locale: Locale) -> String {
        locale.localized("Bu bir tahmindir; bankanızın fiilî tahakkuku kuruş farkı gösterebilir. Yatırım tavsiyesi değildir.")
    }

    /// Net kazancın sıfır kalma nedeni.
    enum ZeroEarningsReason: Hashable {
        case belowMinimumBalance
        case requirementConsumesEntireBalance
        case belowOneKurus

        /// Özet'teki cümle.
        func text(_ locale: Locale) -> String {
            switch self {
            case .belowMinimumBalance: return locale.localized("Bu ürün daha yüksek bir bakiye gerektiriyor")
            case .requirementConsumesEntireBalance: return locale.localized("Vadesiz şartı toplam bakiyenin tamamını kapsıyor")
            case .belowOneKurus: return locale.localized("Bu tutarda kazanç kuruşun altında kalıyor")
            }
        }
    }

    /// Uyarının ağırlığı; görünüm renge çevirir (error → ember, info → slate).
    enum Tone: Hashable {
        case info
        case error
    }

    struct Warning: Hashable {
        let text: String
        let tone: Tone
    }

    /// Net kazanç sıfırken nedeni; kazanç varsa ya da neden belirsizse nil.
    static func zeroEarningsReason(for result: InterestResult, nights: Int) -> ZeroEarningsReason? {
        guard result.netInterest <= 0 else { return nil }
        let diagnostics = result.diagnostics
        if diagnostics.contains(.belowMinimumBalance) {
            return .belowMinimumBalance
        }
        if diagnostics.contains(.requirementConsumesEntireBalance) {
            return .requirementConsumesEntireBalance
        }
        if result.totalBalance > 0, nights > 0,
           result.totalGrossInterest == 0, !diagnostics.contains(.zeroRate) {
            return .belowOneKurus
        }
        return nil
    }

    /// Sonuca eşlik eden girdi uyarıları (tanılama sırasıyla).
    static func warnings(for diagnostics: [CalculationDiagnostic], locale: Locale) -> [Warning] {
        let hundred = Decimal(100).percentText(fractionDigits: 0...0, locale: locale)
        return diagnostics.compactMap { diagnostic in
            switch diagnostic {
            case .idlePercentageAboveOneHundred:
                return Warning(text: locale.localized("Vadesiz yüzdesi \(hundred)'e sınırlandı."), tone: .error)
            case .deductionRatesExceedTotal:
                return Warning(text: locale.localized("Kesinti oranları toplamı \(hundred)'ü aşıyor."), tone: .error)
            case .unusuallyHighRate:
                return Warning(text: locale.localized("Girdiğiniz oran çok yüksek — günlük oran girmiş olabilir misiniz?"), tone: .info)
            default:
                return nil
            }
        }
    }
}
