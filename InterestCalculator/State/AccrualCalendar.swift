//
//  AccrualCalendar.swift
//  InterestCalculator
//
//  Gerçek takvim ↔ motor eşlemesi. Foundation Calendar/Date burada YAŞAR ki
//  saf motor (Engine/) tarih tiplerinden uzak kalsın. Görevleri: bir tarihin
//  hafta gününü çıkarmak, iki tarih arası gece sayısını saymak ve bitiş hafta
//  sonuna düşerse ilk iş gününe (Pazartesi) çekmek.
//

import Foundation

enum AccrualCalendar {

    /// Gregoryen takvim, cihaz zaman dilimi. "Ertesi gün 00:00" sınırı bu
    /// takvimin `startOfDay`'idir.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Bugünün 00:00'ı — başlangıç varsayılanı.
    static func today() -> Date {
        calendar.startOfDay(for: Date())
    }

    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Foundation'ın 1=Pazar…7=Cumartesi düzenini motorun `Weekday`'ine çevirir.
    static func weekday(for date: Date) -> Weekday {
        switch calendar.component(.weekday, from: date) {
        case 2:  return .monday
        case 3:  return .tuesday
        case 4:  return .wednesday
        case 5:  return .thursday
        case 6:  return .friday
        case 7:  return .saturday
        default: return .sunday   // 1
        }
    }

    /// `start`'a `n` gün ekler (gün başı normalize ederek).
    static func addNights(_ n: Int, to start: Date) -> Date {
        let base = calendar.startOfDay(for: start)
        return calendar.date(byAdding: .day, value: n, to: base) ?? base
    }

    /// İki tarih arası tam gün (gece) sayısı; gün başına normalize edilir.
    static func nights(from start: Date, to end: Date) -> Int {
        let s = calendar.startOfDay(for: start)
        let e = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: s, to: e).day ?? 0
    }

    /// Bitiş Cumartesi/Pazar'a düşerse bir sonraki Pazartesi'ye çeker.
    static func snappedOffWeekend(_ date: Date) -> Date {
        switch weekday(for: date) {
        case .saturday: return addNights(2, to: date)
        case .sunday:   return addNights(1, to: date)
        default:        return calendar.startOfDay(for: date)
        }
    }

    /// Başlangıç + gün sayısından bitiş tarihi (hafta sonundan kaçırılmış).
    static func endDate(start: Date, nights: Int) -> Date {
        snappedOffWeekend(addNights(max(1, nights), to: start))
    }

    /// İstenen gün sayısını normalize eder: bitişi hesapla, hafta sonundan kaçır,
    /// gerçek (normalize) gün sayısını döndür. Sonuç [1, 365] aralığındadır.
    static func normalizedNights(start: Date, requested: Int) -> Int {
        let clamped = max(1, min(requested, 365))
        let rawEnd = addNights(clamped, to: start)
        let snapped = snappedOffWeekend(rawEnd)
        return max(1, nights(from: start, to: snapped))
    }
}
