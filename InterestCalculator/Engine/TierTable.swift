//
//  TierTable.swift
//  InterestCalculator
//
//  Kademeli kural tablosu. Yalnız ÜST SINIR saklanır; alt sınır bir önceki
//  kademeden türetilir, böylece boşluk/çakışma yapısal olarak temsil edilemez.
//

import Foundation

/// Kademeli kural tablosu. Değer tipi jenerik; hem vadesiz şartı hem (v2'de)
/// oran dilimleri için kullanılır.
///
/// Değişmez: `tiers` daima normalize edilmiştir — artan sıralı, tekilleştirilmiş
/// üst sınırlar ve son kademe daima sınırsız (`upperBound == nil`). Bu yüzden
/// hiçbir bakiye "hiçbir kademeye uymayan" duruma düşemez.
nonisolated struct TierTable<Value: Hashable & Sendable>: Hashable, Sendable {
    /// Tek bir kademe. Yalnız üst sınır saklanır.
    nonisolated struct Tier: Hashable, Sendable {
        /// Kademenin ÜST sınırı — DIŞLAYICI. `nil` = son/sınırsız kademe.
        /// Alt sınır bir önceki kademeden türetilir.
        var upperBound: Money?
        var value: Value
    }

    /// `resolve(for:)` sonucu: seçilen kademe ve indeksi.
    nonisolated struct Match: Hashable, Sendable {
        var index: Int
        var tier: Tier
    }

    /// Normalize edilmiş kademeler. Değişmez dışarıdan bozulamaz.
    private(set) var tiers: [Tier]

    /// Normalizasyon sırasında üretilen tanılamalar (ör. tekilleştirme, sınır
    /// kırpma). Motor bunları sonucun `diagnostics`'ine ekler.
    private(set) var normalizationDiagnostics: [CalculationDiagnostic]

    /// TOPLAM kurucu: geçersiz durumu temsil edilemez hale getirir.
    /// Boş liste tek `fallback` kademesine dönüşür; negatif sınırlar 0'a çekilir;
    /// tekrar eden sınırlarda sonuncusu kazanır; son kademe sınırsızlaştırılır.
    init(normalizing rawTiers: [Tier], fallback: Value) {
        var diagnostics: [CalculationDiagnostic] = []

        // Boş liste -> tek fallback kademesi.
        if rawTiers.isEmpty {
            self.tiers = [Tier(upperBound: nil, value: fallback)]
            self.normalizationDiagnostics = [.emptyTierTableReplacedWithFallback]
            return
        }

        // Negatif üst sınır -> 0'a çek.
        var working: [Tier] = rawTiers.map { tier in
            if let bound = tier.upperBound, bound < 0 {
                diagnostics.append(.tierBoundBelowZeroClamped)
                return Tier(upperBound: 0, value: tier.value)
            }
            return tier
        }

        // Sınırlılar üst sınıra göre artan; sınırsız (nil) daima sona.
        working.sort { lhs, rhs in
            switch (lhs.upperBound, rhs.upperBound) {
            case let (l?, r?): return l < r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return false
            }
        }

        // Aynı üst sınır (nil dahil) tekrar ediyorsa sonuncusu kazanır.
        var deduped: [Tier] = []
        for tier in working {
            if let last = deduped.last, last.upperBound == tier.upperBound {
                deduped[deduped.count - 1] = tier
                diagnostics.append(.duplicateTierBoundMerged)
            } else {
                deduped.append(tier)
            }
        }

        // Son kademe sınırsız değilse -> nil'e zorla ("hiçbir kademeye uymayan
        // bakiye" durumu doğamaz).
        if var last = deduped.last, last.upperBound != nil {
            last.upperBound = nil
            deduped[deduped.count - 1] = last
            diagnostics.append(.lastTierForcedUnbounded)
        }

        self.tiers = deduped
        self.normalizationDiagnostics = diagnostics
    }

    /// Bir tutarın düştüğü kademeyi bulur. Üst sınır DIŞLAYICI:
    /// `amount < upperBound` ise o kademe seçilir; tam sınır üst kademeye düşer.
    /// Son kademe sınırsız olduğu için daima bir eşleşme döner (TOPLAM fonksiyon).
    func resolve(for amount: Money) -> Match {
        for (index, tier) in tiers.enumerated() {
            if tier.upperBound == nil || amount < tier.upperBound! {
                return Match(index: index, tier: tier)
            }
        }
        // Normalizasyon son kademeyi sınırsız yapar; buraya ulaşılmaz.
        let lastIndex = tiers.count - 1
        return Match(index: lastIndex, tier: tiers[lastIndex])
    }
}
