//
//  RateRule.swift
//  InterestCalculator
//
//  Faiz oranı kuralı ve ilan tabanı (brüt/net).
//

import Foundation

/// İlan edilen oranın brüt mü net mi olduğu. Türkiye'de mevduat oranları sık sık
/// net olarak da ilan edilir; ayrım motorda ayrı ele alınır.
nonisolated enum RateBasis: Hashable, Sendable {
    /// Brüt: stopaj öncesi ilan edilmiş oran.
    case gross
    /// Net: stopaj sonrası ilan edilmiş oran.
    case net
}

/// Faiz oranı kuralı. v1'de yalnız düz oran vardır.
///
/// Kademeye göre oran ASLA vadesiz şartı kademesine eklenmez; bu iki eksen
/// piyasada farklı eşiklerde çalışır. (v2: `case tiered(...)`.)
nonisolated enum RateRule: Hashable, Sendable {
    case flat(Percentage)
}
