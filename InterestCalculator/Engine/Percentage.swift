//
//  Percentage.swift
//  InterestCalculator
//
//  Yüzde oranı — belirsizliği tipte kapatan değer tipi.
//

import Foundation

/// Yüzde oranı. İç temsil daima kesirdir: %45 -> `fraction` 0.45.
///
/// Tek giriş noktası `percent(_:)`; bu yüzden `let r: Percentage = 45` gibi
/// bir ifade yazılamaz — okuyucuya %45 mi %4500 mü olduğunu söylemeyeceği için
/// `ExpressibleBy*Literal` bilinçli olarak EKLENMEZ.
nonisolated struct Percentage: Hashable, Sendable, Comparable {
    /// Kesir biçimi: %45 -> 0.45. Kampanya/kriz oranları %100'ü (1.0) aşabilir,
    /// bu yüzden bu tip üst sınır dayatmaz.
    let fraction: Decimal

    private init(fraction: Decimal) {
        self.fraction = fraction
    }

    /// Yüzde değerinden kurar: `percent(45)` -> %45. TEK giriş noktası.
    static func percent(_ value: Decimal) -> Percentage {
        Percentage(fraction: value / 100)
    }

    /// Sıfır oran (%0).
    static let zero = Percentage(fraction: 0)

    /// Yüzde değeri: 0.45 -> 45.
    var percentValue: Decimal { fraction * 100 }

    /// Tutara uygular. YUVARLAMA YAPMAZ — yuvarlama motorun sorumluluğudur.
    func applied(to amount: Money) -> Money {
        amount * fraction
    }

    /// [%0, %100] aralığına kırpar. Yalnız kırpılması gereken alanlarda
    /// (vadesiz yüzdesi, stopaj) çağrılır — faiz oranı için ASLA, çünkü oran
    /// %100'ü aşabilir.
    func clampedToZeroThroughOneHundred() -> Percentage {
        if fraction < 0 { return .zero }
        if fraction > 1 { return Percentage(fraction: 1) }
        return self
    }

    /// Yalnızca negatifi sıfıra çeker; üst sınır koymaz (faiz oranı için).
    func clampedToNonNegative() -> Percentage {
        fraction < 0 ? .zero : self
    }

    static func < (lhs: Percentage, rhs: Percentage) -> Bool {
        lhs.fraction < rhs.fraction
    }
}
