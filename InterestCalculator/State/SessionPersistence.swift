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
    /// Max geçmişi. Opsiyonel: bu alandan önce kaydedilmiş oturumlar da çözülsün.
    var maxHistory: [MaxPlanRecord]?
}

enum SessionStore {
    private static let key = "karliGece.session.v1"

    static func load() -> SessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            debugPrint("[SessionStore] Kayıtlı oturum bulunamadı.")
            return nil
        }
        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data)
        } catch {
            debugPrint("[SessionStore] Kayıtlı oturum çözülemedi, yok sayıldı: \(error)")
            return nil
        }
    }

    static func save(_ snapshot: SessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            debugPrint("[SessionStore] Oturum JSON'a kodlanamadı, kayıt atlandı.")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
        debugPrint("[SessionStore] Oturum kaydedildi: \(snapshot.banks.count) banka, \(snapshot.maxHistory?.count ?? 0) Max kaydı, \(data.count) bayt.")
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        debugPrint("[SessionStore] Kayıtlı oturum silindi.")
    }
}
