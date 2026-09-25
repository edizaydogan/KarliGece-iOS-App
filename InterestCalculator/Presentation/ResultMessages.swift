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
    static let disclaimer = "Bu bir tahmindir; bankanızın fiilî tahakkuku kuruş farkı gösterebilir. Yatırım tavsiyesi değildir."

    /// Net kazancın sıfır kalma nedeni.
    enum ZeroEarningsReason: Hashable {
        case belowMinimumBalance
        case requirementConsumesEntireBalance
        case belowOneKurus

        /// Özet'teki cümle.
        var text: String {
            switch self {
            case .belowMinimumBalance: return "Bu ürün daha yüksek bir bakiye gerektiriyor"
            case .requirementConsumesEntireBalance: return "Vadesiz şartı toplam bakiyenin tamamını kapsıyor"
            case .belowOneKurus: return "Bu tutarda kazanç kuruşun altında kalıyor"
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
    static func warnings(for diagnostics: [CalculationDiagnostic]) -> [Warning] {
        diagnostics.compactMap { diagnostic in
            switch diagnostic {
            case .idlePercentageAboveOneHundred:
                return Warning(text: "Vadesiz yüzdesi %100'e sınırlandı.", tone: .error)
            case .deductionRatesExceedTotal:
                return Warning(text: "Kesinti oranları toplamı %100'ü aşıyor.", tone: .error)
            case .unusuallyHighRate:
                return Warning(text: "Girdiğiniz oran çok yüksek — günlük oran girmiş olabilir misiniz?", tone: .info)
            default:
                return nil
            }
        }
    }
}
