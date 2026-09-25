//
//  CompareCalculator.swift
//  InterestCalculator
//
//  Karşılaştır tablosunun hesabı ve sıralaması. Saf, deterministik; faiz
//  matematiği YAZMAZ — her hücre mevcut `CompoundingEngine.project` çağrısıdır
//  (tek doğruluk kaynağı). Date'e dokunmaz; başlangıç günü dışarıdan gelir.
//

import Foundation

/// Tek bir vade satırındaki bir hücrenin sıralama sonucu.
nonisolated struct CompareRank: Hashable, Sendable {
    /// Satırın en yüksek net kazancı bu hücrede (eşitlikte birden çok hücre).
    var isBest: Bool
    /// En yükseğe göre eksik kalan net tutar; en iyi hücrede ve hepsi eşitken nil.
    var shortfall: Money?
}

nonisolated enum CompareCalculator {

    /// Sabit vadeler (1 gün = 1 gece). Özet'in vadesinden BAĞIMSIZDIR ve hafta
    /// sonu snap'i uygulanmaz: satırlar tam gün sayısını gösterir.
    static let horizons: [Int] = [1, 7, 30, 90, 365]

    /// Her banka için her vadenin valör kurallı bileşik sonucu.
    /// Dış dizi sütun (banka), iç dizi `horizons` sırasıyla vade.
    static func projections(
        balance: Money,
        conditions: [BankCondition],
        withholding: WithholdingRule,
        startWeekday: Weekday
    ) -> [[InterestResult]] {
        conditions.map { condition in
            horizons.map { nights in
                CompoundingEngine.project(
                    initialBalance: balance,
                    startWeekday: startWeekday,
                    nights: nights,
                    condition: condition,
                    withholding: withholding
                )
            }
        }
    }

    /// Bir vade satırının sıralaması. En yüksek net > 0 ve en az bir hücre ondan
    /// düşükse en yüksek(ler) `isBest`, diğerleri farkı taşır; hepsi eşitse
    /// kimse rozet almaz. Her satır AYRI sıralanır — bileşik büyüme uzun vadede
    /// kademeli bir bankayı sınırın üstüne taşıyıp sırayı değiştirebilir.
    static func rank(_ nets: [Money]) -> [CompareRank] {
        guard let maxNet = nets.max(), maxNet > 0,
              nets.contains(where: { $0 < maxNet }) else {
            return nets.map { _ in CompareRank(isBest: false, shortfall: nil) }
        }
        return nets.map { net in
            net == maxNet
                ? CompareRank(isBest: true, shortfall: nil)
                : CompareRank(isBest: false, shortfall: maxNet - net)
        }
    }
}
