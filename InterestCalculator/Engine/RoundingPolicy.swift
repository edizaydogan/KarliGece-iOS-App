//
//  RoundingPolicy.swift
//  InterestCalculator
//
//  Para yuvarlama politikası — tüm 2-hane yuvarlamalar tek noktadan geçer.
//

import Foundation

/// Para yuvarlama politikası (2 ondalık hane).
///
/// Motorun kullandığı sabit mod `standard`'dır; mod tek bir noktada değişir.
/// Golden tablosundaki tüm değerler half-up ve bankers'da AYNI çıktığı için
/// modu ayırt eden tek vaka şudur: `0,005` -> half-up **0,01**, bankers **0,00**.
///
/// NOT (Adım 2/3'te onaylanacak): `standard = .halfUp` varsayımı, Türk
/// bankacılık konvansiyonuna dayanan bir seçimdir; hesaplama adımlarına
/// geçerken kullanıcıyla teyit edilecek.
nonisolated enum RoundingPolicy: Hashable, Sendable {
    /// Yarımlar sıfırdan uzağa (0,005 -> 0,01).
    case halfUp
    /// Yarımlar en yakın çift haneye (0,005 -> 0,00). Karşılaştırma/test için.
    case bankers

    /// Motorun her yerde kullandığı sabit mod.
    static let standard = RoundingPolicy.halfUp

    /// Bir `Money` değerini 2 ondalık haneye yuvarlar.
    func round2(_ value: Money) -> Money {
        var input = value
        var result = Money()
        NSDecimalRound(&result, &input, 2, mode)
        return result
    }

    private var mode: NSDecimalNumber.RoundingMode {
        switch self {
        case .halfUp: return .plain
        case .bankers: return .bankers
        }
    }
}
