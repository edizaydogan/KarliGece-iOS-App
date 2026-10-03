//
//  HoldingLedger.swift
//  InterestCalculator
//
//  Bakiyelerim'in faiz işletmesi. Saf, deterministik; faiz matematiği YAZMAZ —
//  her valör gününün kazancı `CompoundingEngine.project` çağrısıdır (tek
//  doğruluk kaynağı). Saati okumaz; "bugün" dışarıdan `CalendarDay` olarak gelir.
//
//  Kural (kullanıcı tanımı): uygulama her açılışta, gün geçtiyse kazancı
//  bakiyenin üzerine ekler ve kaydeder. Ekleme Özet'in valör modeline uyar:
//   • Hafta içi gecenin net faizi ertesi gün 00:00'da eklenir.
//   • Cuma, Cumartesi ve Pazar geceleri Cuma bakiyesi üzerinden işler, toplamı
//     Pazartesi 00:00'da eklenir. Cumartesi/Pazar açılışında bakiye değişmez;
//     biriken tutar `pendingInterest` ile gösterilir.
//  Bakiye yalnız valör günlerinde ilerlediği için işletme idempotenttir: aynı
//  gün ikinci açılış hiçbir şey eklemez, kaydedilmeden kapanan uygulama bir
//  sonraki açılışta aynı sonucu yeniden üretir.
//

import Foundation

nonisolated enum HoldingLedger {

    /// Kayıt başına tutulan en fazla hareket (yaklaşık üç aylık iş günü).
    static let entryLimit = 60

    /// `day` itibarıyla valörü gelmiş en son gün: hafta içi günün kendisi,
    /// Cumartesi/Pazar'da önceki Cuma.
    static func lastValueDay(onOrBefore day: CalendarDay) -> CalendarDay {
        switch day.weekday {
        case .saturday: return day.adding(-1)
        case .sunday:   return day.adding(-2)
        default:        return day
        }
    }

    /// `day`'in gecesinin kazancının eklendiği gün: ilk iş günü (Cuma → Pazartesi).
    static func nextValueDay(after day: CalendarDay) -> CalendarDay {
        var next = day.adding(1)
        while next.weekday.isWeekend {
            next = next.adding(1)
        }
        return next
    }

    /// Yeni kayıt: bakiye `day` itibarıyla geçerlidir, ilk hareket giriştir.
    static func open(bankID: UUID, bankName: String, balance: Money, on day: CalendarDay) -> Holding {
        var holding = Holding(id: UUID(), bankID: bankID, bankName: bankName,
                              balance: 0, asOf: day, enteredBalance: 0, enteredOn: day, entries: [])
        setBalance(&holding, to: balance, on: day)
        return holding
    }

    /// Kullanıcının girdiği bakiye: `day` itibarıyla geçerlidir, "eklenen faiz"
    /// sıfırlanır. Bekleyen hafta sonu kazancı bırakılır — yeni tutar bankadaki
    /// bakiyedir. Eski hareketler tarihçe olarak kalır.
    static func setBalance(_ holding: inout Holding, to balance: Money, on day: CalendarDay) {
        let amount = max(0, balance)
        record(HoldingEntry(id: UUID(), day: day, kind: .balanceSet,
                            change: amount - holding.balance, balanceAfter: amount), in: &holding)
        holding.balance = amount
        holding.enteredBalance = amount
        holding.enteredOn = day
        holding.asOf = day
    }

    /// Bakiyeyi `today` itibarıyla valörü gelmiş gecelerle bileşikler. Her valör
    /// günü ayrı bir hareket üretir (Pazartesi 3 gece). Eklenen hareketleri, en
    /// yeni başta döndürür; eklenecek bir şey yoksa boş.
    ///
    /// Valör günlerinde bölmek tek parça `project` ile birebir aynıdır: motor da
    /// birikmiş kazancı tam bu günlerde bakiyeye yazar.
    @discardableResult
    static func accrue(_ holding: inout Holding, condition: BankCondition,
                       withholding: WithholdingRule, through today: CalendarDay) -> [HoldingEntry] {
        let target = lastValueDay(onOrBefore: today)
        var added: [HoldingEntry] = []
        var day = holding.asOf
        while true {
            let valueDay = nextValueDay(after: day)
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

    /// Geçmiş ama valörü henüz gelmemiş gecelerin net faizi: Cumartesi'den
    /// itibaren Cuma (ve Cumartesi) gecesinin kazancı, Pazartesi eklenecek.
    /// Hafta içi (işletmeden sonra) 0'dır.
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
