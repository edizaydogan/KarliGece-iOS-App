//
//  Weekday.swift
//  InterestCalculator
//
//  Haftanın günü — saf, deterministik aritmetik. Foundation Date/Calendar
//  KULLANMAZ; gerçek takvim eşlemesi State katmanındaki AccrualCalendar'ın işidir.
//  Motor bu tiple valör (değer tarihi) kuralını yalnız hafta günü üzerinden yürütür.
//

import Foundation

/// Haftanın günü. Ham değer Pazartesi=0 ... Pazar=6 (aritmetik mod 7 için).
nonisolated enum Weekday: Int, Hashable, Sendable, CaseIterable {
    case monday = 0
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    /// Cumartesi/Pazar hafta sonudur (bankacılıkta valör ilerlemez).
    var isWeekend: Bool { self == .saturday || self == .sunday }

    /// Hafta içi (Pzt–Cum) — bir sonraki iş günü valörü bu günlerde ilerler.
    var isBusinessDay: Bool { !isWeekend }

    /// `days` gün sonrasının günü. Negatif de çalışır (çift modulo).
    func advanced(by days: Int) -> Weekday {
        let index = ((rawValue + days) % 7 + 7) % 7
        return Weekday(rawValue: index)!
    }

    /// Ertesi gün.
    var next: Weekday { advanced(by: 1) }
}
