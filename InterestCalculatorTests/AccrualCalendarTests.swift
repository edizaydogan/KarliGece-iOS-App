//
//  AccrualCalendarTests.swift
//  InterestCalculatorTests
//
//  Gerçek takvim eşlemesi + hafta sonu → Pazartesi snap. Bilinen bir hafta
//  üzerinden pinlenir: 2026-01-05 Pazartesi … 2026-01-11 Pazar, 01-12 Pazartesi.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Vade Takvimi (AccrualCalendar)")
struct AccrualCalendarTests {

    /// Öğlen 12:00 — DST/gün-başı sınır belirsizliğini eler.
    private func day(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = dd; c.hour = 12
        return AccrualCalendar.calendar.date(from: c)!
    }

    @Test("Hafta günü eşlemesi (Foundation 1=Pazar → Weekday)")
    func weekdayMapping() {
        #expect(AccrualCalendar.weekday(for: day(2026, 1, 5)) == .monday)
        #expect(AccrualCalendar.weekday(for: day(2026, 1, 8)) == .thursday)
        #expect(AccrualCalendar.weekday(for: day(2026, 1, 9)) == .friday)
        #expect(AccrualCalendar.weekday(for: day(2026, 1, 10)) == .saturday)
        #expect(AccrualCalendar.weekday(for: day(2026, 1, 11)) == .sunday)
        #expect(AccrualCalendar.weekday(for: day(2026, 1, 12)) == .monday)
    }

    @Test("Hafta sonu bitişleri ilk iş gününe (Pazartesi) çekilir")
    func snapping() {
        // Cumartesi 10 → Pazartesi 12
        #expect(AccrualCalendar.weekday(for: AccrualCalendar.snappedOffWeekend(day(2026, 1, 10))) == .monday)
        #expect(AccrualCalendar.nights(from: day(2026, 1, 5),
                                       to: AccrualCalendar.snappedOffWeekend(day(2026, 1, 10))) == 7)
        // Pazar 11 → Pazartesi 12
        #expect(AccrualCalendar.nights(from: day(2026, 1, 5),
                                       to: AccrualCalendar.snappedOffWeekend(day(2026, 1, 11))) == 7)
        // Cuma 9 → değişmez
        #expect(AccrualCalendar.nights(from: day(2026, 1, 5),
                                       to: AccrualCalendar.snappedOffWeekend(day(2026, 1, 9))) == 4)
    }

    @Test("normalizedNights · hafta sonuna düşen istek Pazartesi'ye taşınır")
    func normalized() {
        // Pazartesi başlangıç, 5 istek → Cumartesi → Pazartesi = 7
        #expect(AccrualCalendar.normalizedNights(start: day(2026, 1, 5), requested: 5) == 7)
        // Pazartesi başlangıç, 4 istek → Cuma = 4 (değişmez)
        #expect(AccrualCalendar.normalizedNights(start: day(2026, 1, 5), requested: 4) == 4)
        // Cuma başlangıç, 1 istek → Cumartesi → Pazartesi = 3
        #expect(AccrualCalendar.normalizedNights(start: day(2026, 1, 9), requested: 1) == 3)
        // En az 1 gece.
        #expect(AccrualCalendar.normalizedNights(start: day(2026, 1, 5), requested: 0) == 1)
        // Üst sınır 365.
        #expect(AccrualCalendar.normalizedNights(start: day(2026, 1, 5), requested: 10_000) <= 367)
    }

    @Test("endDate · başlangıç + gün sayısı, iş günü")
    func endDateDerivation() {
        let end = AccrualCalendar.endDate(start: day(2026, 1, 5), nights: 4)
        #expect(AccrualCalendar.weekday(for: end) == .friday)
        #expect(AccrualCalendar.nights(from: day(2026, 1, 5), to: end) == 4)

        // Bitiş hafta sonuysa Pazartesi'ye çekilir.
        let snappedEnd = AccrualCalendar.endDate(start: day(2026, 1, 9), nights: 1)
        #expect(AccrualCalendar.weekday(for: snappedEnd) == .monday)
    }
}
