//
//  UserProfile.swift
//  InterestCalculator
//
//  Profil sekmesinin kişisel bilgileri, görünüm ve dil tercihi. Hesap/sunucu
//  yok: hepsi oturumla birlikte yalnız bu cihazda saklanır.
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
}

/// Arayüz dili. Metinler kodda Türkçe yazılır (kaynak dil); İngilizceleri
/// `Localizable.xcstrings`'tedir. Ham değer .lproj klasörünün dil kodudur.
nonisolated enum AppLanguage: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"

    var id: Self { self }

    /// Seçicideki ad, her dil kendi dilinde: arayüz hangi dilde olursa olsun
    /// kullanıcı kendi dilini tanır.
    var nativeName: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }

    /// Metinlerin, sayıların ve tarihlerin yerel ayarı: seçilen dil + cihazın
    /// bölgesi. iOS'un uygulama başına dil ayarı da böyle birleştirir: Türkiye
    /// bölgesinde English → en_TR (metin ve tarih İngilizce, sayılar ₺100.000,00).
    var locale: Locale {
        Locale(languageCode: Locale.LanguageCode(rawValue), languageRegion: Locale.current.region)
    }
}
