//
//  HoldingLedger.swift
//  InterestCalculator
//
//  Bakiyelerim'in faiz işletmesi. Saf, deterministik; faiz matematiği YAZMAZ —
//  her valör gününün kazancı `CompoundingEngine.project` çağrısıdır (tek
//  doğruluk kaynağı). Saati okumaz; "bugün" dışarıdan `CalendarDay` olarak gelir.
//
//  Kural (kullanıcı tanımı): uygulama her açılışta, gün geçtiyse kazancı
//  bakiyenin üzerine ekler ve kaydeder. Hafta içi gecenin net faizi ertesi gün
//  00:00'da eklenir. Hafta sonu kaydın kuralına göre işler:
//   • 3 gecelik (Özet'in valör modeli): Cuma, Cumartesi ve Pazar geceleri Cuma
//     bakiyesi üzerinden işler, toplamı Pazartesi 00:00'da eklenir.
//     Cumartesi/Pazar açılışında bakiye değişmez; biriken tutar
//     `pendingInterest` ile gösterilir.
//   • 1 gecelik: hafta sonu da her gecenin faizi ertesi gün eklenir.
//  Birlikte eklenen geceler bir "faiz bloğu"dur: 1 gece ya da Cuma–Pazar'ın 3
//  gecesi. Girilen bakiye bugünün bloğundan faiz alır; 3 gecelikte hafta sonu
//  girilen bakiye Cuma'dan beri bankada sayılır (Pazartesi 3 gece). "Bugünün
//  faizini kaçırdım" bu bloğu atlar, faiz bir sonrakinden başlar.
//  Bakiye yalnız valör günlerinde ilerlediği için işletme idempotenttir: aynı
//  gün ikinci açılış hiçbir şey eklemez, kaydedilmeden kapanan uygulama bir
//  sonraki açılışta aynı sonucu yeniden üretir.
//

import Foundation

nonisolated enum HoldingLedger {

    /// Kayıt başına tutulan en fazla hareket (yaklaşık üç aylık iş günü).
    static let entryLimit = 60

    /// Bir valör günü ve o gün eklenecek gece sayısı.
    nonisolated struct Credit: Hashable, Sendable {
        var day: CalendarDay
        var nights: Int
    }

    /// `day` itibarıyla valörü gelmiş en son gün, yani `day`'i içeren faiz
    /// bloğunun ilk gecesi: 3 gecelikte hafta içi günün kendisi,
    /// Cumartesi/Pazar'da önceki Cuma; 1 gecelikte her gün kendisi.
    static func lastValueDay(onOrBefore day: CalendarDay,
                             weekendInterest: WeekendInterest = .threeNights) -> CalendarDay {
        guard weekendInterest == .threeNights else { return day }
        switch day.weekday {
        case .saturday: return day.adding(-1)
        case .sunday:   return day.adding(-2)
        default:        return day
        }
    }

    /// `day`'in gecesinin kazancının eklendiği gün: 3 gecelikte ilk iş günü
    /// (Cuma → Pazartesi), 1 gecelikte ertesi gün.
    static func nextValueDay(after day: CalendarDay,
                             weekendInterest: WeekendInterest = .threeNights) -> CalendarDay {
        var next = day.adding(1)
        while weekendInterest == .threeNights && next.weekday.isWeekend {
            next = next.adding(1)
        }
        return next
    }

    /// `day`'de girilen bakiyenin faizinin başladığı gece: bugünün bloğunun ilk
    /// gecesi, bugünün faizi kaçırıldıysa bir sonraki bloğun.
    static func accrualStart(forEntryOn day: CalendarDay, weekendInterest: WeekendInterest,
                             missesTodaysInterest: Bool) -> CalendarDay {
        let blockStart = lastValueDay(onOrBefore: day, weekendInterest: weekendInterest)
        return missesTodaysInterest ? nextValueDay(after: blockStart, weekendInterest: weekendInterest) : blockStart
    }

    /// Bugünün faiz bloğunun gece sayısı — "bugünün faizini kaçırdım" bu kadar
    /// geceyi atlar: 3 gecelikte Cuma–Pazar 3, diğer her durumda 1.
    static func todaysInterestNights(on day: CalendarDay, weekendInterest: WeekendInterest) -> Int {
        let blockStart = lastValueDay(onOrBefore: day, weekendInterest: weekendInterest)
        return blockStart.nights(to: nextValueDay(after: blockStart, weekendInterest: weekendInterest))
    }

    /// Düzenleme sayfasındaki "bugünün faizini kaçırdım"ın başlangıç değeri:
    /// bakiye bugün girildiyse girişteki seçim, önceki bir gün girildiyse işaretsiz.
    static func missesTodaysInterest(_ holding: Holding, on day: CalendarDay) -> Bool {
        holding.enteredOn == day && holding.missedEntryDayInterest
    }

    /// Bakiyenin gösterildiği gün: faiz başladıysa `asOf`, bugünün faizi
    /// kaçırıldığı için valör ileri bir günse giriş günü.
    static func balanceDay(_ holding: Holding, today: CalendarDay) -> CalendarDay {
        holding.asOf <= today ? holding.asOf : holding.enteredOn
    }

    /// Yeni kayıt: bakiye `day` itibarıyla geçerlidir, ilk hareket giriştir.
    static func open(bankID: UUID, bankName: String, balance: Money, on day: CalendarDay,
                     weekendInterest: WeekendInterest = .threeNights,
                     missesTodaysInterest: Bool = false) -> Holding {
        var holding = Holding(id: UUID(), bankID: bankID, bankName: bankName,
                              balance: 0, asOf: day, enteredBalance: 0, enteredOn: day, entries: [],
                              weekendInterest: weekendInterest)
        setBalance(&holding, to: balance, on: day, missesTodaysInterest: missesTodaysInterest)
        return holding
    }

    /// Kullanıcının girdiği bakiye: `day` itibarıyla geçerlidir, "eklenen faiz"
    /// sıfırlanır. Faiz kaydın kuralıyla bugünün bloğundan (kaçırıldıysa bir
    /// sonrakinden) başlar; bekleyen kazanç yeni tutar üzerinden yeniden
    /// hesaplanır — yeni tutar bankadaki bakiyedir. Eski hareketler tarihçe
    /// olarak kalır; aynı gün aynı tutarı yeniden girmek (yalnız seçim
    /// değiştiyse) ikinci bir hareket yazmaz.
    static func setBalance(_ holding: inout Holding, to balance: Money, on day: CalendarDay,
                           missesTodaysInterest: Bool = false) {
        let amount = max(0, balance)
        let repeatsLastEntry = holding.entries.first.map {
            $0.kind == .balanceSet && $0.day == day && $0.balanceAfter == amount
        } ?? false
        if !repeatsLastEntry {
            record(HoldingEntry(id: UUID(), day: day, kind: .balanceSet,
                                change: amount - holding.balance, balanceAfter: amount), in: &holding)
        }
        holding.balance = amount
        holding.enteredBalance = amount
        holding.enteredOn = day
        holding.missedEntryDayInterest = missesTodaysInterest
        holding.asOf = accrualStart(forEntryOn: day, weekendInterest: holding.weekendInterest,
                                    missesTodaysInterest: missesTodaysInterest)
    }

    /// Hafta sonu kuralını değiştirir; bakiye, eklenen faiz ve hareketler
    /// korunur. Girişten bu yana faiz eklenmediyse girişin başlangıç gecesi yeni
    /// kurala göre yeniden hesaplanır (3 gecelikte Cumartesi girişi Cuma'dan
    /// sayılıyordu, 1 gecelikte Cumartesi'den sayılır). Faiz eklendiyse
    /// eklenmemiş geceler yeni kuralla eklenir.
    static func setWeekendInterest(_ holding: inout Holding, to weekendInterest: WeekendInterest) {
        guard weekendInterest != holding.weekendInterest else { return }
        let entryStart = accrualStart(forEntryOn: holding.enteredOn, weekendInterest: holding.weekendInterest,
                                      missesTodaysInterest: holding.missedEntryDayInterest)
        holding.weekendInterest = weekendInterest
        // Her faiz eklemesi `asOf`'u ileri taşır: eşitlik "girişten beri faiz yok" demektir.
        if holding.asOf == entryStart {
            holding.asOf = accrualStart(forEntryOn: holding.enteredOn, weekendInterest: weekendInterest,
                                        missesTodaysInterest: holding.missedEntryDayInterest)
        }
    }

    /// Düzenleme sayfasının kaydı (banka değişimi hariç). Tutar ya da "bugünün
    /// faizini kaçırdım" seçimi değiştiyse bakiye `day` itibarıyla bu seçimlerle
    /// yeniden girilir; yalnız hafta sonu kuralı değiştiyse bakiye korunur.
    static func edit(_ holding: inout Holding, balance: Money, weekendInterest: WeekendInterest,
                     missesTodaysInterest: Bool, on day: CalendarDay) {
        if balance != holding.balance
            || missesTodaysInterest != Self.missesTodaysInterest(holding, on: day) {
            holding.weekendInterest = weekendInterest
            setBalance(&holding, to: balance, on: day, missesTodaysInterest: missesTodaysInterest)
        } else {
            setWeekendInterest(&holding, to: weekendInterest)
        }
    }

    /// Bakiyeyi `today` itibarıyla valörü gelmiş gecelerle bileşikler. Her valör
    /// günü ayrı bir hareket üretir (3 gecelikte Pazartesi 3 gece). Eklenen
    /// hareketleri, en yeni başta döndürür; eklenecek bir şey yoksa boş.
    ///
    /// Valör günlerinde bölmek tek parça `project` ile birebir aynıdır: motor da
    /// birikmiş kazancı tam bu günlerde bakiyeye yazar. 1 gecelikte her valör
    /// günü tek gecedir, motorun hafta sonu toplaması devreye girmez.
    @discardableResult
    static func accrue(_ holding: inout Holding, condition: BankCondition,
                       withholding: WithholdingRule, through today: CalendarDay) -> [HoldingEntry] {
        let weekendInterest = holding.weekendInterest
        let target = lastValueDay(onOrBefore: today, weekendInterest: weekendInterest)
        var added: [HoldingEntry] = []
        var day = holding.asOf
        while true {
            let valueDay = nextValueDay(after: day, weekendInterest: weekendInterest)
            guard valueDay <= target else { break }
            let nights = day.nights(to: valueDay)
            let net = CompoundingEngine.project(
                initialBalance: holding.balance,
                startWeekday: day.weekday,
                nights: nights,
                condition: condition,
                withholding: withholding
            ).netInterest
            holding.balance += net
            let entry = HoldingEntry(id: UUID(), day: valueDay, kind: .interest(nights: nights),
                                     change: net, balanceAfter: holding.balance)
            record(entry, in: &holding)
            added.insert(entry, at: 0)
            day = valueDay
        }
        holding.asOf = day
        return added
    }

    /// `today`'den sonraki ilk valör günü ve o gün eklenecek gece sayısı.
    /// Valörü gelmiş ama henüz işletilmemiş günler sayılmaz: işletme onları
    /// bugün ekler.
    static func nextCredit(_ holding: Holding, after today: CalendarDay) -> Credit {
        let weekendInterest = holding.weekendInterest
        let target = lastValueDay(onOrBefore: today, weekendInterest: weekendInterest)
        var start = holding.asOf
        var valueDay = nextValueDay(after: start, weekendInterest: weekendInterest)
        while valueDay <= target {
            start = valueDay
            valueDay = nextValueDay(after: start, weekendInterest: weekendInterest)
        }
        return Credit(day: valueDay, nights: start.nights(to: valueDay))
    }

    /// Geçmiş ama valörü henüz gelmemiş gecelerin net faizi: 3 gecelikte
    /// Cumartesi'den itibaren Cuma (ve Cumartesi) gecesinin kazancı, Pazartesi
    /// eklenecek. Hafta içi ve 1 gecelikte (işletmeden sonra) 0'dır.
    static func pendingInterest(_ holding: Holding, condition: BankCondition,
                                withholding: WithholdingRule, today: CalendarDay) -> Money {
        let nights = holding.asOf.nights(to: today)
        guard nights > 0 else { return 0 }
        return CompoundingEngine.project(
            initialBalance: holding.balance,
            startWeekday: holding.asOf.weekday,
            nights: nights,
            condition: condition,
            withholding: withholding
        ).netInterest
    }

    /// Mevcut bakiyenin bir gecelik net faizi (tahmin).
    static func nightlyNet(_ holding: Holding, condition: BankCondition,
                           withholding: WithholdingRule) -> Money {
        InterestEngine.calculate(
            InterestInput(totalBalance: holding.balance, nights: 1,
                          condition: condition, withholding: withholding)
        ).netInterest
    }

    /// Hareketi en başa ekler; sınırı aşan en eski hareketler düşer.
    private static func record(_ entry: HoldingEntry, in holding: inout Holding) {
        holding.entries.insert(entry, at: 0)
        if holding.entries.count > entryLimit {
            holding.entries.removeLast(holding.entries.count - entryLimit)
        }
    }
}
