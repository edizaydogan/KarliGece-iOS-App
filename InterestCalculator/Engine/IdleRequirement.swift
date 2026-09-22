//
//  IdleRequirement.swift
//  InterestCalculator
//
//  Bankanın vadesiz tutma şartı. ÖZYİNELEME YOK.
//

import Foundation

/// Kademeli vadesiz şartında bir kademenin gerektirdiği tutar.
/// Yüzde okuması DAİMA toplam bakiye üzerindendir.
nonisolated enum TierRequirement: Hashable, Sendable {
    case percentage(Percentage)
    case fixedAmount(Money)
}

/// Bankanın vadesiz (faiz işlemeyen) bakiye tutma şartı.
///
/// `tiered` içindeki tablo `TierRequirement` taşır — vadesiz şartı kademeleri
/// ile (v2'deki) oran dilimleri BAĞIMSIZ eksenlerdir, iç içe geçmez.
nonisolated enum IdleRequirement: Hashable, Sendable {
    case none
    case percentage(Percentage)
    case fixedAmount(Money)
    case tiered(TierTable<TierRequirement>)
}
