//
//  SessionPersistence.swift
//  InterestCalculator
//
//  Tüm oturumun UserDefaults'a JSON olarak kaydı. Motor tiplerine dokunmaz;
//  yalnız taslak (draft) katmanını serileştirir.
//

import Foundation

/// Kaydedilen tüm oturum durumu.
struct SessionSnapshot: Codable {
    var balanceText: String
    var withholdingText: String
    var nights: Int
    var selectedBankID: UUID?
    var selectedTab: AppTab
    var banks: [BankConditionDraft]
}

enum SessionStore {
    private static let key = "karliGece.session.v1"

    static func load() -> SessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    static func save(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
