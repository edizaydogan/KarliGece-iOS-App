//
//  HoldingLedgerTests.swift
//  InterestCalculatorTests
//
//  Bakiyelerim'in faiz işletmesi: valör günleri, hafta içi bileşik, hafta sonu
//  kuralı (3 gecelikte Pazartesi toplaması, 1 gecelikte her gece), girişin faiz
//  bloğu ve "bugünün faizini kaçırdım", kural değişimi, idempotentlik ve
//  motorla birebir tutarlılık. Golden'lar CompoundingEngineTests'teki
//  senaryoyla aynıdır (100.000 ₺, %45 brüt, stopaj %17,5, ACT/365, vadesiz
//  şartsız) ve elle hesaplanmıştır. Günler gerçek takvimdendir:
//  2026-10-05 Pazartesi = 9408. gün.
//

import Testing
import Foundation
@testable import InterestCalculator

@Suite("Bakiyelerim Defteri (HoldingLedger)")
struct HoldingLedgerTests {

    /// 2026-10-05 Pazartesi.
    private let monday = CalendarDay(index: 9408)
    private var friday: CalendarDay { monday.adding(4) }
    private var saturday: CalendarDay { monday.adding(5) }
    private var sunday: CalendarDay { monday.adding(6) }
    private var nextMonday: CalendarDay { monday.adding(7) }
    private let flat = BankCondition(name: "g", rateRule: .flat(.percent(45)))
    private var withholding: WithholdingRule { .single(.percent(d("17.5"))) }

    private func open(_ balance: Decimal, on day: CalendarDay, weekend: WeekendInterest = .threeNights,
                      missed: Bool = false) -> Holding {
        HoldingLedger.open(bankID: UUID(), bankName: "g", balance: balance, on: day,
                           weekendInterest: weekend, missesTodaysInterest: missed)
    }

    @discardableResult
    private func accrue(_ holding: inout Holding, through day: CalendarDay,
                        condition: BankCondition? = nil) -> [HoldingEntry] {
        HoldingLedger.accrue(&holding, condition: condition ?? flat, withholding: withholding, through: day)
    }

    private func pending(_ holding: Holding, on day: CalendarDay) -> Money {
        HoldingLedger.pendingInterest(holding, condition: flat, withholding: withholding, today: day)
    }

    /// Bölme invariant'larının koşulları.
    private var conditions: [BankCondition] {
        [
            flat,
            BankCondition(name: "A", rateRule: .flat(.percent(45)), idleRequirement: .percentage(.percent(10))),
            BankCondition(name: "C", rateRule: .flat(.percent(40)), rateBasis: .net),
            // 49.990 ₺ bileşiklenerek 50.000 ₺ uçurumunu geçer: kademe her gece motorda değişir.
            BankCondition(name: "K", rateRule: .flat(.percent(42)), idleRequirement: .tiered(cliffIdleTable())),
        ]
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

    @Test("Valör günleri: 3 gecelikte hafta sonu önceki Cuma, Cuma–Pazar gecesi Pazartesi; 1 gecelikte her gün ertesi gün")
    func valueDays() {
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

        for offset in 0...6 {
            let day = monday.adding(offset)
            #expect(HoldingLedger.lastValueDay(onOrBefore: day, weekendInterest: .oneNight) == day)
            #expect(HoldingLedger.nextValueDay(after: day, weekendInterest: .oneNight) == day.adding(1))
        }
    }

    @Test("Bugünün faiz bloğu: 3 gecelikte Cuma–Pazar 3 gece, diğer her gün 1 gece; kaçırılınca faiz sonraki bloktan başlar")
    func todaysBlock() {
        // Pazartesi … Pazar.
        let threeNights = [1, 1, 1, 1, 3, 3, 3]
        let threeStart = [0, 1, 2, 3, 4, 4, 4]       // Cumartesi/Pazar girişi Cuma'dan sayılır
        let threeMissedStart = [1, 2, 3, 4, 7, 7, 7] // Perşembe → Cuma bloğu; Cuma–Pazar → Pazartesi gecesi
        for offset in 0...6 {
            let day = monday.adding(offset)
            #expect(HoldingLedger.todaysInterestNights(on: day, weekendInterest: .threeNights) == threeNights[offset])
            #expect(HoldingLedger.accrualStart(forEntryOn: day, weekendInterest: .threeNights,
                                               missesTodaysInterest: false) == monday.adding(threeStart[offset]))
            #expect(HoldingLedger.accrualStart(forEntryOn: day, weekendInterest: .threeNights,
                                               missesTodaysInterest: true) == monday.adding(threeMissedStart[offset]))

            #expect(HoldingLedger.todaysInterestNights(on: day, weekendInterest: .oneNight) == 1)
            #expect(HoldingLedger.accrualStart(forEntryOn: day, weekendInterest: .oneNight,
                                               missesTodaysInterest: false) == day)
            #expect(HoldingLedger.accrualStart(forEntryOn: day, weekendInterest: .oneNight,
                                               missesTodaysInterest: true) == day.adding(1))
        }
    }

    @Test("Yeni kayıt: bakiye giriş günü itibarıyla, ilk hareket giriş, varsayılan 3 gecelik")
    func opening() {
        let holding = open(d("100000"), on: monday)
        #expect(holding.balance == d("100000"))
        #expect(holding.asOf == monday)
        #expect(holding.enteredBalance == d("100000"))
        #expect(holding.enteredOn == monday)
        #expect(holding.accruedInterest == 0)
        #expect(holding.weekendInterest == .threeNights)
        #expect(!holding.missedEntryDayInterest)
        #expect(holding.entries.map(\.kind) == [.balanceSet])
        #expect(holding.entries.first?.change == d("100000"))
    }

    @Test("Golden · Pazartesi girilen bakiye Cuma'ya kadar her gün bileşiklenir", .tags(.golden))
    func weekdayAccrual() {
        var holding = open(d("100000"), on: monday)
        // Aynı gün: valörü gelen gece yok.
        #expect(accrue(&holding, through: monday).isEmpty)

        let added = accrue(&holding, through: friday)   // Cuma açılışı
        #expect(added.map(\.change) == [d("102.02"), d("101.92"), d("101.81"), d("101.71")])
        #expect(added.map(\.day) == [monday.adding(4), monday.adding(3), monday.adding(2), monday.adding(1)])
        #expect(added.allSatisfy { $0.kind == .interest(nights: 1) })
        #expect(holding.balance == d("100407.46"))   // Pzt-4 gece golden'ı
        #expect(holding.accruedInterest == d("407.46"))
        #expect(holding.asOf == friday)
        #expect(holding.entries.count == 5)
        #expect(holding.entries.first?.balanceAfter == d("100407.46"))
        #expect(holding.entries.last?.kind == .balanceSet)
    }

    @Test("Golden · 3 gecelik: hafta sonu bakiye değişmez; Cuma–Pazar kazancı Pazartesi tek harekette eklenir", .tags(.golden))
    func weekendWaitsForMonday() {
        var holding = open(d("100000"), on: monday)
        accrue(&holding, through: friday)
        let fridayState = holding

        for weekend in [saturday, sunday] {
            #expect(accrue(&holding, through: weekend).isEmpty)
            #expect(holding == fridayState)
        }
        // Bekleyen: Cumartesi'de Cuma gecesi, Pazar'da Cuma + Cumartesi (aynı Cuma bakiyesi).
        #expect(pending(holding, on: saturday) == d("102.13"))
        #expect(pending(holding, on: sunday) == d("204.26"))

        let added = accrue(&holding, through: nextMonday)
        #expect(added.map(\.kind) == [.interest(nights: 3)])
        #expect(added.first?.change == d("306.39"))   // 3 × 102,13: hafta sonu kendi içinde bileşiklenmez
        #expect(holding.balance == d("100713.85"))
        #expect(pending(holding, on: nextMonday) == 0)
    }

    @Test("Golden · 3 gecelik: Cumartesi girilen bakiye Cuma'dan sayılır, Pazartesi 3 gece eklenir", .tags(.golden))
    func threeNightsOpenedOnSaturday() {
        var holding = open(d("100000"), on: saturday)
        #expect(holding.asOf == friday)
        #expect(holding.enteredOn == saturday)
        #expect(accrue(&holding, through: sunday).isEmpty)
        #expect(pending(holding, on: saturday) == d("101.71"))
        #expect(pending(holding, on: sunday) == d("203.42"))
        let added = accrue(&holding, through: nextMonday)
        #expect(added.map(\.kind) == [.interest(nights: 3)])
        #expect(added.first?.change == d("305.13"))   // 3 × 101,71
        #expect(holding.balance == d("100305.13"))

        // Pazar girişi de aynı Cuma bloğunu alır.
        var onSunday = open(d("100000"), on: sunday)
        accrue(&onSunday, through: nextMonday)
        #expect(onSunday.balance == d("100305.13"))
    }

    @Test("Golden · 3 gecelik, bugünün faizi kaçırıldı: Cumartesi girişi hafta sonunu atlar, Pazartesi gecesinden işler", .tags(.golden))
    func threeNightsMissedOnSaturday() {
        var holding = open(d("100000"), on: saturday, missed: true)
        #expect(holding.asOf == nextMonday)
        #expect(holding.missedEntryDayInterest)
        #expect(pending(holding, on: sunday) == 0)
        #expect(accrue(&holding, through: nextMonday).isEmpty)
        #expect(holding.balance == d("100000"))
        let added = accrue(&holding, through: nextMonday.adding(1))
        #expect(added.map(\.kind) == [.interest(nights: 1)])
        #expect(holding.balance == d("100101.71"))
    }

    @Test("3 gecelik, kaçırıldı: Perşembe girişi Cuma'nın 3 gecesini alır; Cuma girişi Pazartesi gecesinden işler", .tags(.edgeCase))
    func threeNightsMissedAroundFriday() {
        var thursday = open(d("100000"), on: monday.adding(3), missed: true)
        #expect(accrue(&thursday, through: friday).isEmpty)   // Perşembe gecesi işlemedi
        #expect(accrue(&thursday, through: nextMonday).map(\.kind) == [.interest(nights: 3)])
        #expect(thursday.balance == d("100305.13"))

        var onFriday = open(d("100000"), on: friday, missed: true)
        #expect(accrue(&onFriday, through: nextMonday).isEmpty)
        #expect(accrue(&onFriday, through: nextMonday.adding(1)).map(\.change) == [d("101.71")])
    }

    @Test("Golden · 1 gecelik: hafta sonu da her gece ertesi gün eklenir ve bileşiklenir", .tags(.golden))
    func oneNightCompoundsWeekend() {
        var holding = open(d("100000"), on: monday, weekend: .oneNight)
        accrue(&holding, through: saturday)
        #expect(holding.balance == d("100509.59"))   // Cuma gecesi Cumartesi eklendi
        #expect(pending(holding, on: saturday) == 0)

        let added = accrue(&holding, through: nextMonday)
        #expect(added.map(\.change) == [d("102.33"), d("102.23")])
        #expect(added.map(\.day) == [nextMonday, sunday])
        #expect(holding.entries.filter { $0.kind != .balanceSet }.count == 7)
        #expect(holding.entries.allSatisfy { $0.kind == .balanceSet || $0.kind == .interest(nights: 1) })
        #expect(holding.balance == d("100714.15"))   // 3 gecelikte aynı hafta 100.713,85
    }

    @Test("Golden · 1 gecelik: Cumartesi girişi bu geceden işler; kaçırılınca Pazar gecesinden", .tags(.golden))
    func oneNightOpenedOnSaturday() {
        var holding = open(d("100000"), on: saturday, weekend: .oneNight)
        #expect(holding.asOf == saturday)
        #expect(accrue(&holding, through: sunday).map(\.change) == [d("101.71")])
        #expect(accrue(&holding, through: nextMonday).map(\.change) == [d("101.81")])
        #expect(holding.balance == d("100203.52"))

        var missed = open(d("100000"), on: saturday, weekend: .oneNight, missed: true)
        #expect(missed.asOf == sunday)
        #expect(accrue(&missed, through: sunday).isEmpty)
        #expect(accrue(&missed, through: nextMonday).map(\.change) == [d("101.71")])
    }

    @Test("Kural değişimi giriş günü: girişin başlangıç gecesi yeni kurala göre yeniden hesaplanır", .tags(.edgeCase))
    func weekendInterestChangeOnEntryDay() {
        // 3 gecelikte Cuma'dan sayılan Cumartesi girişi: 1 gecelikte Cumartesi
        // bakiyesi Cuma gecesinin faizini zaten içerir, Cumartesi'den işler.
        var holding = open(d("100000"), on: saturday)
        HoldingLedger.setWeekendInterest(&holding, to: .oneNight)
        #expect(holding.weekendInterest == .oneNight)
        #expect(holding.asOf == saturday)
        #expect(accrue(&holding, through: sunday).map(\.change) == [d("101.71")])

        var missed = open(d("100000"), on: saturday, missed: true)   // 3 gecelik → Pazartesi
        HoldingLedger.setWeekendInterest(&missed, to: .oneNight)
        #expect(missed.asOf == sunday)
        HoldingLedger.setWeekendInterest(&missed, to: .threeNights)
        #expect(missed.asOf == nextMonday)
    }

    @Test("Golden · Kural değişimi faiz eklendikten sonra: eklenmemiş geceler yeni kuralla eklenir, gece kaybolmaz", .tags(.golden))
    func weekendInterestChangeAfterAccrual() {
        var holding = open(d("100000"), on: monday)
        accrue(&holding, through: friday)   // 100.407,46; Cuma gecesi bekliyor
        HoldingLedger.setWeekendInterest(&holding, to: .oneNight)
        #expect(holding.asOf == friday)
        #expect(accrue(&holding, through: saturday).map(\.change) == [d("102.13")])
        #expect(holding.balance == d("100509.59"))

        // Cumartesi yeniden 3 gecelik: Cumartesi ve Pazar geceleri Pazartesi toplu.
        HoldingLedger.setWeekendInterest(&holding, to: .threeNights)
        #expect(accrue(&holding, through: sunday).isEmpty)
        let added = accrue(&holding, through: nextMonday)
        #expect(added.map(\.kind) == [.interest(nights: 2)])
        #expect(added.first?.change == d("204.46"))   // 2 × 102,23
        #expect(holding.balance == d("100714.05"))
        #expect(holding.accruedInterest == d("714.05"))
    }

    @Test("Düzenleme: tutar ya da kaçırıldı seçimi değişirse bugün itibarıyla yeniden giriş; yalnız kural değişirse bakiye korunur")
    func editing() {
        // Aynı gün yalnız seçim değişti: valör yeniden hesaplanır, ikinci giriş hareketi yazılmaz.
        var holding = open(d("100000"), on: saturday)
        HoldingLedger.edit(&holding, balance: d("100000"), weekendInterest: .threeNights,
                           missesTodaysInterest: true, on: saturday)
        #expect(holding.asOf == nextMonday)
        #expect(holding.entries.count == 1)
        #expect(HoldingLedger.missesTodaysInterest(holding, on: saturday))
        #expect(!HoldingLedger.missesTodaysInterest(holding, on: sunday))   // ertesi gün işaretsiz başlar
        HoldingLedger.edit(&holding, balance: d("100000"), weekendInterest: .threeNights,
                           missesTodaysInterest: false, on: saturday)
        #expect(holding.asOf == friday)
        #expect(holding.entries.count == 1)

        // Önceki gün girilmiş, faiz eklenmiş bakiye; aynı tutarla "kaçırdım": bugün itibarıyla yeniden girilir.
        var weekday = open(d("100000"), on: monday)
        accrue(&weekday, through: monday.adding(2))   // 100.203,52
        HoldingLedger.edit(&weekday, balance: d("100203.52"), weekendInterest: .threeNights,
                           missesTodaysInterest: true, on: monday.adding(2))
        #expect(weekday.balance == d("100203.52"))
        #expect(weekday.accruedInterest == 0)
        #expect(weekday.enteredOn == monday.adding(2))
        #expect(weekday.asOf == monday.adding(3))
        #expect(weekday.entries.first?.kind == .balanceSet)
        #expect(weekday.entries.first?.change == 0)

        // Yalnız kural: bakiye, eklenen faiz, hareketler ve faizi eklenmemiş ilk gece korunur.
        var kept = open(d("100000"), on: monday)
        accrue(&kept, through: monday.adding(2))
        let before = kept
        HoldingLedger.edit(&kept, balance: before.balance, weekendInterest: .oneNight,
                           missesTodaysInterest: false, on: monday.adding(2))
        #expect(kept.weekendInterest == .oneNight)
        #expect(kept.balance == before.balance)
        #expect(kept.accruedInterest == before.accruedInterest)
        #expect(kept.entries == before.entries)
        #expect(kept.asOf == before.asOf)

        // Tutar ve kural birlikte: yeni tutar yeni kuralla girilir.
        var both = open(d("100000"), on: monday)
        HoldingLedger.edit(&both, balance: d("150000"), weekendInterest: .oneNight,
                           missesTodaysInterest: false, on: saturday)
        #expect(both.weekendInterest == .oneNight)
        #expect(both.asOf == saturday)
        #expect(both.enteredBalance == d("150000"))
    }

    @Test("Sonraki faiz: valör günü ve gece sayısı; işletilmemiş valör günleri atlanır")
    func nextCredit() {
        typealias Credit = HoldingLedger.Credit
        let weekdayEntry = open(d("100000"), on: monday)
        #expect(HoldingLedger.nextCredit(weekdayEntry, after: monday) == Credit(day: monday.adding(1), nights: 1))
        // Pazartesi'den beri işletilmedi: Cuma'ya kadarki günleri işletme bugün ekler, sıradaki Pazartesi.
        #expect(HoldingLedger.nextCredit(weekdayEntry, after: saturday) == Credit(day: nextMonday, nights: 3))

        #expect(HoldingLedger.nextCredit(open(d("1"), on: saturday), after: saturday)
                == Credit(day: nextMonday, nights: 3))
        #expect(HoldingLedger.nextCredit(open(d("1"), on: saturday, missed: true), after: saturday)
                == Credit(day: nextMonday.adding(1), nights: 1))
        #expect(HoldingLedger.nextCredit(open(d("1"), on: saturday, weekend: .oneNight), after: saturday)
                == Credit(day: sunday, nights: 1))
        #expect(HoldingLedger.nextCredit(open(d("1"), on: monday.adding(3), missed: true), after: monday.adding(3))
                == Credit(day: nextMonday, nights: 3))
    }

    @Test("Bakiyenin günü: valör ileri bir günse (kaçırıldı) giriş günü, değilse faizi eklenmemiş ilk gece")
    func balanceDay() {
        let missed = open(d("1"), on: saturday, missed: true)
        #expect(HoldingLedger.balanceDay(missed, today: saturday) == saturday)
        #expect(HoldingLedger.balanceDay(missed, today: nextMonday) == nextMonday)
        #expect(HoldingLedger.balanceDay(open(d("1"), on: saturday), today: saturday) == friday)
        #expect(HoldingLedger.balanceDay(open(d("1"), on: monday), today: monday) == monday)
    }

    @Test("İşletme idempotent: aynı gün ikinci çağrı hiçbir şey eklemez")
    func idempotent() {
        for weekend in WeekendInterest.allCases {
            var holding = open(d("100000"), on: monday, weekend: weekend)
            accrue(&holding, through: monday.adding(9))
            let once = holding
            #expect(accrue(&holding, through: monday.adding(9)).isEmpty)
            #expect(holding == once)
        }
    }

    @Test("Saat geri alınırsa (bugün < valör günü) hiçbir şey değişmez", .tags(.edgeCase))
    func clockMovedBack() {
        var holding = open(d("100000"), on: monday.adding(3))
        let opened = holding
        #expect(accrue(&holding, through: monday).isEmpty)
        #expect(holding == opened)
        #expect(pending(holding, on: monday) == 0)
    }

    @Test("3 gecelik: valör günlerine bölmek tek parça CompoundingEngine.project ile birebir aynı", .tags(.invariant))
    func matchesSingleProjection() {
        var mismatches: [String] = []
        for condition in conditions {
            for start in 0..<7 {
                for missed in [false, true] {
                    for gap in [1, 2, 3, 6, 10, 31, 90] {
                        let opened = monday.adding(start)
                        var holding = open(d("49990"), on: opened, missed: missed)
                        accrue(&holding, through: opened.adding(gap), condition: condition)
                        let first = HoldingLedger.accrualStart(forEntryOn: opened, weekendInterest: .threeNights,
                                                               missesTodaysInterest: missed)
                        let target = HoldingLedger.lastValueDay(onOrBefore: opened.adding(gap))
                        let nights = max(0, first.nights(to: target))
                        let expected = d("49990") + CompoundingEngine.project(
                            initialBalance: d("49990"), startWeekday: first.weekday, nights: nights,
                            condition: condition, withholding: withholding
                        ).netInterest
                        if holding.balance != expected {
                            mismatches.append("\(condition.name) +\(start) gün, kaçırıldı \(missed), \(gap) gün: \(holding.balance) ≠ \(expected)")
                        }
                    }
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
    }

    @Test("1 gecelik: her gece bir önceki gecenin faiziyle büyümüş bakiyeden işler (tek gecelik motorla birebir)", .tags(.invariant))
    func oneNightMatchesSingleNights() {
        var mismatches: [String] = []
        for condition in conditions {
            for start in 0..<7 {
                for missed in [false, true] {
                    for gap in [1, 2, 3, 6, 10, 31] {
                        let opened = monday.adding(start)
                        var holding = open(d("49990"), on: opened, weekend: .oneNight, missed: missed)
                        accrue(&holding, through: opened.adding(gap), condition: condition)
                        var expected = d("49990")
                        var night = missed ? opened.adding(1) : opened
                        while night < opened.adding(gap) {
                            expected += InterestEngine.calculate(
                                InterestInput(totalBalance: expected, nights: 1,
                                              condition: condition, withholding: withholding)
                            ).netInterest
                            night = night.adding(1)
                        }
                        if holding.balance != expected {
                            mismatches.append("\(condition.name) +\(start) gün, kaçırıldı \(missed), \(gap) gün: \(holding.balance) ≠ \(expected)")
                        }
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

    @Test("Kayıt JSON'da kuruş kaybetmeden geri gelir; gün düz tamsayı, seçimler adıyla")
    func codableRoundTrip() throws {
        var holding = open(d("60000.37"), on: monday, weekend: .oneNight, missed: true)
        accrue(&holding, through: monday.adding(7))
        let data = try JSONEncoder().encode(holding)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"asOf\":9415"))
        #expect(json.contains("\"weekendInterest\":\"oneNight\""))
        #expect(json.contains("\"missedEntryDayInterest\":true"))
        let decoded = try JSONDecoder().decode(Holding.self, from: data)
        #expect(decoded == holding)
        #expect(decoded.balance == holding.balance)
    }

    @Test("Hafta sonu kuralından önce kaydedilmiş kayıt 3 gecelik, kaçırılmamış olarak çözülür")
    func legacyHoldingDecodes() throws {
        var holding = open(d("100000"), on: saturday, weekend: .oneNight, missed: true)
        holding.asOf = saturday   // eski kural: Cumartesi girişi Cumartesi'den
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(holding)) as? [String: Any])
        object["weekendInterest"] = nil
        object["missedEntryDayInterest"] = nil
        let decoded = try JSONDecoder().decode(Holding.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.weekendInterest == .threeNights)
        #expect(!decoded.missedEntryDayInterest)
        #expect(decoded.asOf == saturday)
        #expect(decoded.entries == holding.entries)

        // Eski kayıt eski valörüyle işler: Cumartesi'den Pazartesi'ye 2 gece.
        var legacy = decoded
        let added = accrue(&legacy, through: nextMonday)
        #expect(added.map(\.kind) == [.interest(nights: 2)])
        #expect(legacy.balance == d("100203.42"))
    }
}
