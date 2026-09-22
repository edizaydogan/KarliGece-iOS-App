//
//  CalculationDiagnostic.swift
//  InterestCalculator
//
//  Motorun ürettiği yapısal tanılamalar. METİN İÇERMEZ — kullanıcı metnini
//  Presentation/DiagnosticText üretir.
//

import Foundation

/// Bir tanılamanın ciddiyeti. `.error` olanlar sonucu bloklar.
nonisolated enum DiagnosticSeverity: Hashable, Sendable {
    case info
    case warning
    case error
}

/// Motorun hesap sırasında ürettiği yapısal işaretler. Her biri veri olarak
/// taşınır; kullanıcıya gösterilecek Türkçe metin Presentation katmanında üretilir.
nonisolated enum CalculationDiagnostic: Hashable, Sendable {
    // Girdi temizleme (sanitize) — Adım 1
    case negativeBalanceClamped
    case zeroBalance
    case negativeNightsClamped
    case zeroNights
    case negativeRateClamped
    case zeroRate
    case unusuallyHighRate
    case deductionRatesExceedTotal

    // Kademe normalizasyonu — Adım 1 (TierTable)
    case emptyTierTableReplacedWithFallback
    case tierBoundBelowZeroClamped
    case duplicateTierBoundMerged
    case lastTierForcedUnbounded

    // Bakiye kovaları — Adım 2 (breakdown)
    case idlePercentageAboveOneHundred
    case belowMinimumBalance
    case requirementConsumesEntireBalance
    case cappedInterestBearingAmount

    // Vergi — Adım 3
    case zeroWithholding

    /// Tanılamanın ciddiyeti. `blockingIssues` yalnız `.error` olanları toplar.
    var severity: DiagnosticSeverity {
        switch self {
        case .negativeBalanceClamped,
             .negativeNightsClamped,
             .negativeRateClamped,
             .deductionRatesExceedTotal,
             .idlePercentageAboveOneHundred,
             .emptyTierTableReplacedWithFallback,
             .tierBoundBelowZeroClamped:
            return .error
        case .zeroBalance,
             .unusuallyHighRate,
             .duplicateTierBoundMerged,
             .lastTierForcedUnbounded,
             .belowMinimumBalance,
             .requirementConsumesEntireBalance:
            return .warning
        case .zeroNights,
             .zeroRate,
             .cappedInterestBearingAmount,
             .zeroWithholding:
            return .info
        }
    }
}
