//
//  CalendarDay.swift
//  InterestCalculator
//
//  Saat diliminden bağımsız takvim günü. Kalıcı kayıtlar (Bakiyelerim) günü
//  `Date` olarak değil bununla tutar: `Date` mutlak bir andır ve cihaz başka saat
//  dilimine geçince "gün başı" kayar (İstanbul 00:00 = Londra'da önceki gün
//  22:00), aynı gece ikinci kez işletilir. Gün sayısı ise her saat diliminde
//  aynı takvim gününü gösterir. Date ↔ gün eşlemesi `AccrualCalendar`'dadır.
//

import Foundation

/// 2001-01-01'den (Pazartesi) bu yana geçen gün sayısı. Hafta günü yalnız mod 7
/// aritmetiğidir; `Calendar` gerekmez.
nonisolated struct CalendarDay: Hashable, Comparable, Sendable, Codable {
    var index: Int

    init(index: Int) {
        self.index = index
    }

    /// Haftanın günü — 0. gün Pazartesi.
    var weekday: Weekday { Weekday.monday.advanced(by: index) }

    func adding(_ days: Int) -> CalendarDay {
        CalendarDay(index: index + days)
    }

    /// Bu günden `other`'a kadar geçen gece sayısı (geçmişse negatif).
    func nights(to other: CalendarDay) -> Int {
        other.index - index
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        lhs.index < rhs.index
    }

    // JSON'da düz tamsayı.
    init(from decoder: Decoder) throws {
        index = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(index)
    }
}
