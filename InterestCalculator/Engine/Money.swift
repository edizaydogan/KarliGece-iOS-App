//
//  Money.swift
//  InterestCalculator
//
//  Para tutarları için ondalık tip.
//

import Foundation

/// Para birimi tutarları. `Double` ASLA kullanılmaz — ikili kayan nokta
/// para tutarlarında sessizce bozulur (ör. `Decimal(1234.56)` = 1234.5599...).
///
/// DİKKAT: `nonisolated typealias` DERLENMEZ. Bu alias bilinçli olarak
/// modifier'sizdir; `Decimal` zaten `Sendable` olduğu için izolasyon sorunu
/// üretmez.
typealias Money = Decimal
