//
//  Holding.swift
//  InterestCalculator
//
//  Profil → Bakiyelerim'in kaydı: kullanıcının bir bankada fiilen tuttuğu
//  bakiye ve hareketleri. Yalnız düz değerler taşır (motor tipi yok), bu yüzden
//  Codable'dır. Faiz işletme kuralı `HoldingLedger`'dadır.
//

import Foundation

/// Bir bankadaki gerçek bakiye. Düzenle'deki bankaya id'siyle bağlıdır: faiz o
/// bankanın koşulları ve Düzenle'deki stopajla işler. Her bankada en fazla bir kayıt.
nonisolated struct Holding: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var bankID: UUID
    /// Bankanın son bilinen gösterim adı. Banka Düzenle'den silinirse bu görünür.
    var bankName: String
    /// Valörlenmiş bakiye, `asOf` günü 00:00 itibarıyla.
    var balance: Money
    /// Bakiyenin geçerli olduğu gün. Sonraki faiz bu günün gecesinden başlar.
    var asOf: CalendarDay
    /// Kullanıcının en son girdiği bakiye ve günü; "eklenen faiz" bunun üzerinden.
    var enteredBalance: Money
    var enteredOn: CalendarDay
    /// Hareketler, en yeni başta; en fazla `HoldingLedger.entryLimit`.
    var entries: [HoldingEntry]

    /// Son girişten bu yana eklenen net faiz.
    var accruedInterest: Money { balance - enteredBalance }
}

/// Bakiye hareketi: kullanıcının girişi ya da bir valör gününde eklenen faiz.
nonisolated struct HoldingEntry: Identifiable, Hashable, Sendable, Codable {

    nonisolated enum Kind: Hashable, Sendable, Codable {
        /// Kullanıcı bakiyeyi girdi ya da düzeltti.
        case balanceSet
        /// Valör günü `nights` gecenin net faizi eklendi (Cuma–Pazar: 3 gece).
        case interest(nights: Int)
    }

    var id: UUID
    /// Girişte giriş günü, faizde valör günü (kazancın bakiyeye eklendiği gün).
    var day: CalendarDay
    var kind: Kind
    /// Bakiyedeki değişim: faizde eklenen net, girişte yeni − önceki bakiye.
    var change: Money
    /// Hareket sonrası bakiye.
    var balanceAfter: Money
}
