//
//  DayCountBasis.swift
//  InterestCalculator
//
//  Faiz gün sayımı tabanı.
//

import Foundation

/// Faiz gün sayımı tabanı. v1 UI'da görünmez; model varsayılanı ACT/365.
nonisolated enum DayCountBasis: Hashable, Sendable {
    case actual365
    case actual360

    /// Yıllık gün sayısı. DAİMA >= 1 olduğu için bölme güvenlidir.
    var daysInYear: Int {
        switch self {
        case .actual365: return 365
        case .actual360: return 360
        }
    }
}
