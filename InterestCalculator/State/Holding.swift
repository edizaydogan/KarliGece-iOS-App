//
//  Holding.swift
//  InterestCalculator
//
//  Profil → Bakiyelerim'in kaydı: kullanıcının bir bankada fiilen tuttuğu
//  bakiye ve hareketleri. Yalnız düz değerler taşır (motor tipi yok), bu yüzden
//  Codable'dır. Faiz işletme kuralı `HoldingLedger`'dadır.
//

import Foundation

/// Bankanın hafta sonu faizini nasıl işlettiği. Kayıtla birlikte saklanır ve her
/// hafta sonuna uygulanır.
nonisolated enum WeekendInterest: String, Hashable, Sendable, Codable, CaseIterable {
    /// Hafta sonu dahil her gece 1 gecelik faiz; kazanç ertesi gün eklenir.
    case oneNight
    /// Cuma, Cumartesi ve Pazar geceleri Cuma bakiyesi üzerinden işler, toplamı
    /// Pazartesi eklenir (Özet'in valör modeli). Bu seçimden önceki kayıtların kuralı.
    case threeNights
}

/// Bir bankadaki gerçek bakiye. Düzenle'deki bankaya id'siyle bağlıdır: faiz o
/// bankanın koşulları ve Düzenle'deki stopajla işler. Her bankada en fazla bir kayıt.
nonisolated struct Holding: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var bankID: UUID
    /// Bankanın son bilinen gösterim adı. Banka Düzenle'den silinirse bu görünür.
    var bankName: String
    /// Valörlenmiş bakiye: `asOf` gecesinden önceki tüm faiz eklenmiş.
    var balance: Money
    /// Faizi henüz eklenmemiş ilk gece: sonraki faiz bu günün gecesinden başlar.
    /// Girişte bugünün faiz bloğunun ilk gecesidir; 3 gecelikte hafta sonu girişi
    /// için o haftanın Cuma'sı. "Bugünün faizini kaçırdım" işaretliyse bir sonraki
    /// bloktur, yani ileri bir gün olabilir (Cumartesi girişi → Pazartesi).
    var asOf: CalendarDay
    /// Kullanıcının en son girdiği bakiye ve günü; "eklenen faiz" bunun üzerinden.
    var enteredBalance: Money
    var enteredOn: CalendarDay
    /// Hareketler, en yeni başta; en fazla `HoldingLedger.entryLimit`.
    var entries: [HoldingEntry]
    var weekendInterest: WeekendInterest = .threeNights
    /// Son girişte "Bugünün faizini kaçırdım" işaretliydi: girilen bakiye giriş
    /// gününün faiz bloğunu (1 gece ya da Cuma–Pazar'ın 3 gecesi) almadı.
    var missedEntryDayInterest = false

    /// Son girişten bu yana eklenen net faiz.
    var accruedInterest: Money { balance - enteredBalance }
}

nonisolated extension Holding {
    // Hafta sonu kuralından önce kaydedilmiş oturumlarda iki anahtar yoktur: o
    // zamanki kural (3 gecelik), kaçırılmış faiz yok.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            bankID: try container.decode(UUID.self, forKey: .bankID),
            bankName: try container.decode(String.self, forKey: .bankName),
            balance: try container.decode(Money.self, forKey: .balance),
            asOf: try container.decode(CalendarDay.self, forKey: .asOf),
            enteredBalance: try container.decode(Money.self, forKey: .enteredBalance),
            enteredOn: try container.decode(CalendarDay.self, forKey: .enteredOn),
            entries: try container.decode([HoldingEntry].self, forKey: .entries),
            weekendInterest: try container.decodeIfPresent(WeekendInterest.self, forKey: .weekendInterest) ?? .threeNights,
            missedEntryDayInterest: try container.decodeIfPresent(Bool.self, forKey: .missedEntryDayInterest) ?? false
        )
    }
}

/// Bakiye hareketi: kullanıcının girişi ya da bir valör gününde eklenen faiz.
nonisolated struct HoldingEntry: Identifiable, Hashable, Sendable, Codable {

    nonisolated enum Kind: Hashable, Sendable, Codable {
        /// Kullanıcı bakiyeyi girdi ya da düzeltti.
        case balanceSet
        /// Valör günü `nights` gecenin net faizi eklendi (3 gecelikte Cuma–Pazar: 3 gece).
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
