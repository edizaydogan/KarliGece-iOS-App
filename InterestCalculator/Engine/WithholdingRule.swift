//
//  WithholdingRule.swift
//  InterestCalculator
//
//  Vergi/kesinti kuralı. Brüt faize uygulanan oran satırları.
//

import Foundation

/// Stopaj/kesinti kuralı. Her satır brüt faize uygulanan bir orandır.
///
/// v1 UI tek satır (stopaj) gösterir; model, ileride birden çok kesinti satırını
/// destekleyebilmek için diziyi bugünden taşır. Kesinti oranı hiçbir yerde koda
/// gömülmez — tamamen kullanıcı girdisidir.
nonisolated struct WithholdingRule: Hashable, Sendable {
    /// Tek bir kesinti satırı.
    nonisolated struct Line: Hashable, Sendable {
        var rate: Percentage
    }

    var lines: [Line]

    /// Tek oranlı kesinti (v1 stopaj alanı bunu kurar).
    static func single(_ rate: Percentage) -> WithholdingRule {
        WithholdingRule(lines: [Line(rate: rate)])
    }

    /// Kesinti yok.
    static let none = WithholdingRule(lines: [])
}
