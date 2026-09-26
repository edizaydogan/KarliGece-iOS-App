//
//  EditorField.swift
//  InterestCalculator
//
//  @FocusState kimliği. Kademe alanları satır id'siyle ayrışır.
//

import Foundation

enum EditorField: Hashable {
    case balance
    case withholding
    case rate
    case idlePercentage
    case idleFixed
    case tierUpperBound(UUID)
    case tierAmount(UUID)
    /// Max'ın gün sayısı alanı.
    case planDays
}
