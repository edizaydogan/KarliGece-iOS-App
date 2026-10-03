//
//  HoldingLedgerTests.swift
//  InterestCalculatorTests
//
//  Bakiyelerim'in faiz işletmesi: valör günleri, hafta içi bileşik, hafta sonu
//  Pazartesi toplaması, idempotentlik ve motorla birebir tutarlılık. Golden'lar
//  CompoundingEngineTests'teki senaryoyla aynıdır (100.000 ₺, %45 brüt, stopaj
//  %17,5, ACT/365, vadesiz şartsız) ve elle hesaplanmıştır. Günler gerçek
//  takvimdendir: 2026-10-05 Pazartesi = 9408. gün.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Bakiyelerim Defteri (HoldingLedger)")
struct HoldingLedgerTests {

    /// 2026-10-05 Pazartesi.
    private let monday = CalendarDay(index: 9408)
    private let flat = BankCondition(name: "g", rateRule: .flat(.percent(45)))
    private var withholding: WithholdingRule { .single(.percent(d("17.5"))) }

    private func open(_ balance: Decimal, on day: CalendarDay) -> Holding {
        HoldingLedger.open(bankID: UUID(), bankName: "g", balance: balance, on: day)
    }

    @discardableResult
    private func accrue(_ holding: inout Holding, through day: CalendarDay,
                        condition: BankCondition? = nil) -> [HoldingEntry] {
        HoldingLedger.accrue(&holding, condition: condition ?? flat, withholding: withholding, through: day)
    }

    private func pending(_ holding: Holding, on day: CalendarDay) -> Money {
        HoldingLedger.pendingInterest(holding, condition: flat, withholding: withholding, today: day)
    }

    @Test("Gün aritmetiği: 0. gün Pazartesi, hafta günü mod 7 (negatif de)")
    func calendarDayWeekday() {
        #expect(CalendarDay(index: 0).weekday == .monday)
        #expect(CalendarDay(index: -1).weekday == .sunday)
        #expect(monday.weekday == .monday)
        #expect(monday.adding(4).weekday == .friday)
        #expect(monday.adding(-1).weekday == .sunday)
        #expect(monday.nights(to: monday.adding(3)) == 3)
        #expect(monday.adding(3).nights(to: monday) == -3)
    }

    @Test("Valör günleri: hafta içi gün kendisi, hafta sonu önceki Cuma; Cuma–Pazar gecesi Pazartesi")
    func valueDays() {
        let friday = monday.adding(4), saturday = monday.adding(5)
        let sunday = monday.adding(6), nextMonday = monday.adding(7)
        for offset in 0...4 {
            #expect(HoldingLedger.lastValueDay(onOrBefore: monday.adding(offset)) == monday.adding(offset))
        }
        #expect(HoldingLedger.lastValueDay(onOrBefore: saturday) == friday)
        #expect(HoldingLedger.lastValueDay(onOrBefore: sunday) == friday)
        for offset in 0...3 {
            #expect(HoldingLedger.nextValueDay(after: monday.adding(offset)) == monday.adding(offset + 1))
        }
        #expect(HoldingLedger.nextValueDay(after: friday) == nextMonday)
        #expect(HoldingLedger.nextValueDay(after: saturday) == nextMonday)
        #expect(HoldingLedger.nextValueDay(after: sunday) == nextMonday)
    }

    @Test("Yeni kayıt: bakiye giriş günü itibarıyla, ilk hareket giriş")
    func opening() {
        let holding = open(d("100000"), on: monday)
        #expect(holding.balance == d("100000"))
        #expect(holding.asOf == monday)
        #expect(holding.enteredBalance == d("100000"))
        #expect(holding.enteredOn == monday)
        #expect(holding.accruedInterest == 0)
        #expect(holding.entries.map(\.kind) == [.balanceSet])
        #expect(holding.entries.first?.change == d("100000"))
    }

    @Test("Golden · Pazartesi girilen bakiye Cuma'ya kadar her gün bileşiklenir", .tags(.golden))
    func weekdayAccrual() {
        var holding = open(d("100000"), on: monday)
        // Aynı gün: valörü gelen gece yok.
        #expect(accrue(&holding, through: monday).isEmpty)

        let added = accrue(&holding, through: monday.adding(4))   // Cuma açılışı
        #expect(added.map(\.change) == [d("102.02"), d("101.92"), d("101.81"), d("101.71")])
        #expect(added.map(\.day) == [monday.adding(4), monday.adding(3), monday.adding(2), monday.adding(1)])
        #expect(added.allSatisfy { $0.kind == .interest(nights: 1) })
        #expect(holding.balance == d("100407.46"))   // Pzt-4 gece golden'ı
        #expect(holding.accruedInterest == d("407.46"))
        #expect(holding.asOf == monday.adding(4))
        #expect(holding.entries.count == 5)
        #expect(holding.entries.first?.balanceAfter == d("100407.46"))
        #expect(holding.entries.last?.kind == .balanceSet)
    }

    @Test("Golden · Hafta sonu bakiye değişmez; Cuma–Pazar kazancı Pazartesi tek harekette eklenir", .tags(.golden))
    func weekendWaitsForMonday() {
        var holding = open(d("100000"), on: monday)
        accrue(&holding, through: monday.adding(4))
        let friday = holding

        for weekend in [monday.adding(5), monday.adding(6)] {
            #expect(accrue(&holding, through: weekend).isEmpty)
            #expect(holding == friday)
        }
        // Bekleyen: Cumartesi'de Cuma gecesi, Pazar'da Cuma + Cumartesi (aynı Cuma bakiyesi).
        #expect(pending(holding, on: monday.adding(5)) == d("102.13"))
        #expect(pending(holding, on: monday.adding(6)) == d("204.26"))

        let added = accrue(&holding, through: monday.adding(7))
        #expect(added.map(\.kind) == [.interest(nights: 3)])
        #expect(added.first?.change == d("306.39"))   // 3 × 102,13: hafta sonu kendi içinde bileşiklenmez
        #expect(holding.balance == d("100713.85"))
        #expect(pending(holding, on: monday.adding(7)) == 0)
    }

    @Test("Cumartesi girilen bakiye Pazartesi iki gece kazanır", .tags(.edgeCase))
    func openedOnSaturday() {
        var holding = open(d("100000"), on: monday.adding(5))
        #expect(accrue(&holding, through: monday.adding(6)).isEmpty)
        #expect(pending(holding, on: monday.adding(6)) == d("101.71"))
        let added = accrue(&holding, through: monday.adding(7))
        #expect(added.map(\.kind) == [.interest(nights: 2)])
        #expect(holding.balance == d("100203.42"))
    }

    @Test("İşletme idempotent: aynı gün ikinci çağrı hiçbir şey eklemez")
    func idempotent() {
        var holding = open(d("100000"), on: monday)
        accrue(&holding, through: monday.adding(9))
        let once = holding
        #expect(accrue(&holding, through: monday.adding(9)).isEmpty)
        #expect(holding == once)
    }

    @Test("Saat geri alınırsa (bugün < valör günü) hiçbir şey değişmez", .tags(.edgeCase))
    func clockMovedBack() {
        var holding = open(d("100000"), on: monday.adding(3))
        let opened = holding
        #expect(accrue(&holding, through: monday).isEmpty)
        #expect(holding == opened)
        #expect(pending(holding, on: monday) == 0)
    }

    @Test("Valör günlerine bölmek tek parça CompoundingEngine.project ile birebir aynı", .tags(.invariant))
    func matchesSingleProjection() {
        let conditions = [
            flat,
            BankCondition(name: "A", rateRule: .flat(.percent(45)), idleRequirement: .percentage(.percent(10))),
            BankCondition(name: "C", rateRule: .flat(.percent(40)), rateBasis: .net),
            // 49.990 ₺ bileşiklenerek 50.000 ₺ uçurumunu geçer: kademe her gece motorda değişir.
            BankCondition(name: "K", rateRule: .flat(.percent(42)), idleRequirement: .tiered(cliffIdleTable())),
        ]
        var mismatches: [String] = []
        for condition in conditions {
            for start in 0..<7 {
                for gap in [1, 2, 3, 6, 10, 31, 90] {
                    let opened = monday.adding(start)
                    var holding = open(d("49990"), on: opened)
                    accrue(&holding, through: opened.adding(gap), condition: condition)
                    let target = HoldingLedger.lastValueDay(onOrBefore: opened.adding(gap))
                    let nights = max(0, opened.nights(to: target))
                    let expected = d("49990") + CompoundingEngine.project(
                        initialBalance: d("49990"), startWeekday: opened.weekday, nights: nights,
                        condition: condition, withholding: withholding
                    ).netInterest
                    if holding.balance != expected {
                        mismatches.append("\(condition.name) +\(start) gün, \(gap) gün: \(holding.balance) ≠ \(expected)")
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("Elle güncelleme: yeni bakiye o gün itibarıyla, eklenen faiz sıfırlanır, eski hareketler kalır")
    func setBalance() {
        var holding = open(d("100000"), on: monday)
        accrue(&holding, through: monday.adding(2))
        #expect(holding.balance == d("100203.52"))
        let entriesBefore = holding.entries

        HoldingLedger.setBalance(&holding, to: d("90000"), on: monday.adding(2))
        #expect(holding.balance == d("90000"))
        #expect(holding.enteredBalance == d("90000"))
        #expect(holding.enteredOn == monday.adding(2))
        #expect(holding.asOf == monday.adding(2))
        #expect(holding.accruedInterest == 0)
        #expect(holding.entries.first?.kind == .balanceSet)
        #expect(holding.entries.first?.change == d("-10203.52"))
        #expect(Array(holding.entries.dropFirst()) == entriesBefore)

        // Faiz yeni bakiyeden yürür.
        accrue(&holding, through: monday.adding(3))
        let night = InterestEngine.calculate(makeInput(total: d("90000"), nights: 1, condition: flat,
                                                       withholdingPercent: d("17.5"))).netInterest
        #expect(holding.balance == d("90000") + night)
    }

    @Test("Hareket listesi sınırlı: en yeniler, yeniden eskiye kalır")
    func entryLimit() {
        var holding = open(d("100000"), on: monday)
        accrue(&holding, through: monday.adding(140))   // 20 hafta = 100 valör günü
        #expect(holding.entries.count == HoldingLedger.entryLimit)
        #expect(holding.entries.first?.day == monday.adding(140))
        #expect(holding.entries.allSatisfy { $0.kind != .balanceSet })   // en eski giriş düştü
        #expect(zip(holding.entries, holding.entries.dropFirst()).allSatisfy { $0.day > $1.day })
    }

    @Test("Kayıt JSON'da kuruş kaybetmeden geri gelir; gün düz tamsayıdır")
    func codableRoundTrip() throws {
        var holding = open(d("60000.37"), on: monday)
        accrue(&holding, through: monday.adding(7))
        let data = try JSONEncoder().encode(holding)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"asOf\":9415"))
        let decoded = try JSONDecoder().decode(Holding.self, from: data)
        #expect(decoded == holding)
        #expect(decoded.balance == holding.balance)
    }
}
