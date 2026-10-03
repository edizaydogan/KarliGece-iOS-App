//
//  UserProfile.swift
//  InterestCalculator
//
//  Profil sekmesinin kişisel bilgileri ve görünüm tercihi. Hesap/sunucu yok:
//  hepsi oturumla birlikte yalnız bu cihazda saklanır.
//

import Foundation

nonisolated struct UserProfile: Hashable, Sendable, Codable {
    var firstName: String = ""
    var lastName: String = ""

    /// "Ad Soyad"; ikisi de boşsa nil.
    var fullName: String? {
        let parts = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Avatar için baş harfler, Türkçe büyük harfle ("ilker ışık" → "İI"); ad yoksa nil.
    var initials: String? {
        let letters = [firstName, lastName].compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).first
        }
        guard !letters.isEmpty else { return nil }
        return String(letters).uppercased(with: Locale(identifier: "tr_TR"))
    }
}

/// Renk düzeni tercihi. `.system` cihazın ayarını izler.
nonisolated enum AppAppearance: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "Sistem"
        case .light:  return "Açık"
        case .dark:   return "Koyu"
        }
    }
}
